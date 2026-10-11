package com.example.bluechat.bluechat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.bluetooth.BluetoothAdapter
import android.os.Binder
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

class BluetoothForegroundService : Service() {

    private val binder = LocalBinder()
    lateinit var bluetoothManager: BluetoothConnectionManager
    private var scheduler: ScheduledExecutorService? = null
    private var isFullyInitialized = false

    inner class LocalBinder : Binder() {
        fun getService(): BluetoothForegroundService = this@BluetoothForegroundService
    }

    override fun onCreate() {
        super.onCreate()
        bluetoothManager = BluetoothConnectionManager(this)
        
        createNotificationChannel()

        // On Android 14+, startForeground with foregroundServiceType='connectedDevice'
        // requires BLUETOOTH_CONNECT permission or it crashes with SecurityException.
        // Wrap it in try-catch so a fresh-install without permissions doesn't kill the app.
        val hasBtPermission = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            checkSelfPermission(android.Manifest.permission.BLUETOOTH_CONNECT) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
        } else {
            true
        }

        if (hasBtPermission) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    startForeground(
                        NOTIFICATION_ID,
                        createNotification(),
                        android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
                    )
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(
                        NOTIFICATION_ID,
                        createNotification(),
                        android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
                    )
                } else {
                    startForeground(NOTIFICATION_ID, createNotification())
                }
            } catch (e: Exception) {
                android.util.Log.e("BlueChat", "startForeground failed: ${e.message}")
                // Cannot run as foreground service — stop gracefully, don't crash
                stopSelf()
                return
            }
        } else {
            // Permissions not yet granted — service was started prematurely.
            // Stop self cleanly without crashing the app.
            android.util.Log.w("BlueChat", "BluetoothForegroundService started without BLUETOOTH_CONNECT permission. Stopping.")
            stopSelf()
            return
        }

        // Register bluetooth state receiver to start server/reconnection loop automatically
        val filter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
        registerReceiver(bluetoothReceiver, filter)

        // Start server initially if bluetooth is enabled
        val adapter = BluetoothAdapter.getDefaultAdapter()
        if (adapter != null && adapter.isEnabled) {
            bluetoothManager.startServer()
        }

        startAutoReconnectionLoop()
        isFullyInitialized = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Make sure it runs
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder {
        return binder
    }

    override fun onDestroy() {
        super.onDestroy()
        scheduler?.shutdownNow()
        if (isFullyInitialized) {
            try {
                unregisterReceiver(bluetoothReceiver)
            } catch (e: Exception) {}
            try {
                bluetoothManager.disconnectAll()
            } catch (e: Exception) {}
        }
    }

    private val bluetoothReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == BluetoothAdapter.ACTION_STATE_CHANGED) {
                val state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)
                if (state == BluetoothAdapter.STATE_ON) {
                    // Bluetooth turned on, start hosting
                    bluetoothManager.startServer()
                } else if (state == BluetoothAdapter.STATE_OFF) {
                    // Bluetooth turned off, stop everything
                    bluetoothManager.stopServer()
                }
            }
        }
    }

    private fun updateBluetoothName() {
        val adapter = BluetoothAdapter.getDefaultAdapter()
        if (adapter != null && adapter.isEnabled) {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val username = prefs.getString("flutter.username", null)
            if (!username.isNullOrEmpty()) {
                val targetName = "BlueChat_$username"
                if (adapter.name != targetName) {
                    try {
                        adapter.name = targetName
                        android.util.Log.d("BlueChat", "Bluetooth adapter successfully renamed to $targetName")
                    } catch (e: SecurityException) {
                        android.util.Log.e("BlueChat", "Failed to rename Bluetooth adapter: SecurityException", e)
                    }
                }
            }
        }
    }

    private fun startAutoReconnectionLoop() {
        scheduler = Executors.newSingleThreadScheduledExecutor()
        scheduler?.scheduleAtFixedRate({
            val adapter = BluetoothAdapter.getDefaultAdapter()
            if (adapter != null && adapter.isEnabled) {
                // 1. Ensure server is running to accept connections
                bluetoothManager.startServer()

                // 2. Fetch known peers and bonded devices, and try to connect to disconnected ones
                val targetAddresses = bluetoothManager.getSavedPeerAddresses(applicationContext).toMutableSet()
                try {
                    val bonded = adapter.bondedDevices
                    if (bonded != null) {
                        for (d in bonded) {
                            targetAddresses.add(d.address)
                        }
                    }
                } catch (e: SecurityException) {
                    android.util.Log.e("BlueChat", "SecurityException reading bonded devices: ${e.message}")
                }

                for (address in targetAddresses) {
                    if (!bluetoothManager.isConnected(address) && !bluetoothManager.isConnecting(address)) {
                        bluetoothManager.connectToDevice(address)
                    }
                }

                // 3. Update adapter name if needed
                updateBluetoothName()

                // 4. Periodically restart discovery to scan for nearby BlueChat devices
                try {
                    if (adapter.isDiscovering) {
                        adapter.cancelDiscovery()
                    }
                    bluetoothManager.startDiscovery()
                } catch (e: SecurityException) {
                    android.util.Log.e("BlueChat", "SecurityException in auto discovery loop: ${e.message}")
                }
            }
        }, 3, 15, TimeUnit.SECONDS)
    }

    fun updateForegroundTypes(hasMic: Boolean, hasCamera: Boolean) {
        val hasBtPermission = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            checkSelfPermission(android.Manifest.permission.BLUETOOTH_CONNECT) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
        } else {
            true
        }

        if (!hasBtPermission) return

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                var type = android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
                if (hasMic) {
                    type = type or android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                }
                if (hasCamera) {
                    type = type or android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
                }
                startForeground(NOTIFICATION_ID, createNotification(), type)
                android.util.Log.d("BlueChat", "Updated foreground service types to: $type")
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, createNotification(), android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
            } else {
                startForeground(NOTIFICATION_ID, createNotification())
            }
        } catch (e: Exception) {
            android.util.Log.e("BlueChat", "updateForegroundTypes failed: ${e.message}")
        }
    }

    companion object {
        private const val NOTIFICATION_ID = 8888
        private const val CHANNEL_ID = "BlueChat_Background_Channel"
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "BlueChat Background Service",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(serviceChannel)
        }
    }

    private fun createNotification(): Notification {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            notificationIntent,
            PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("BlueChat Offline Service")
            .setContentText("Listening for Bluetooth group connections...")
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth) // Use system bluetooth icon
            .setContentIntent(pendingIntent)
            .build()
    }
}
