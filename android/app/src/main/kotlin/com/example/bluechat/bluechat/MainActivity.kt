package com.example.bluechat.bluechat

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.net.Uri
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.util.Log
import androidx.annotation.NonNull
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var bluetoothService: BluetoothForegroundService? = null
    private val bluetoothManager: BluetoothConnectionManager?
        get() = bluetoothService?.bluetoothManager

    private var deviceDiscoverySink: EventChannel.EventSink? = null
    private var connectionStateSink: EventChannel.EventSink? = null
    private var messageSink: EventChannel.EventSink? = null
    private var transferProgressSink: EventChannel.EventSink? = null

    companion object {
        private const val TAG = "BlueChat_MainActivity"
        private const val METHOD_CHANNEL = "com.example.bluechat/methods"
        private const val EVENT_DISCOVERY = "com.example.bluechat/events/discovery"
        private const val EVENT_CONNECTION = "com.example.bluechat/events/connection"
        private const val EVENT_MESSAGES = "com.example.bluechat/events/messages"
        private const val EVENT_PROGRESS = "com.example.bluechat/events/progress"
        private const val PERMISSION_REQUEST_CODE = 101
    }

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            Log.d(TAG, "Foreground service connected successfully. Wiring up sinks...")
            val binder = service as BluetoothForegroundService.LocalBinder
            bluetoothService = binder.getService()
            bluetoothManager?.let { manager ->
                manager.deviceDiscoverySink = deviceDiscoverySink
                manager.connectionStateSink = connectionStateSink
                manager.messageSink = messageSink
                manager.transferProgressSink = transferProgressSink
                Log.d(TAG, "Sinks successfully restored on service connection.")
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            Log.w(TAG, "Foreground service disconnected abruptly.")
            bluetoothService = null
        }
    }

    private var isServiceBound = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "onCreate: Activity started.")
        
        if (hasBluetoothConnectPermission()) {
            startBluetoothForegroundService()
        } else {
            requestPermissions()
        }
    }

    private fun hasBluetoothConnectPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(this, android.Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(this, android.Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(this, android.Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(this, android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestPermissions() {
        Log.d(TAG, "Requesting required permissions...")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            requestPermissions(
                arrayOf(
                    android.Manifest.permission.BLUETOOTH_CONNECT,
                    android.Manifest.permission.BLUETOOTH_SCAN,
                    android.Manifest.permission.BLUETOOTH_ADVERTISE,
                    android.Manifest.permission.ACCESS_FINE_LOCATION
                ),
                PERMISSION_REQUEST_CODE
            )
        } else {
            requestPermissions(
                arrayOf(android.Manifest.permission.ACCESS_FINE_LOCATION),
                PERMISSION_REQUEST_CODE
            )
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                Log.d(TAG, "Permissions successfully granted by user.")
                startBluetoothForegroundService()
            } else {
                Log.w(TAG, "Required permissions denied by user.")
            }
        }
    }

    fun startBluetoothForegroundService() {
        try {
            Log.d(TAG, "Starting BluetoothForegroundService as foreground service...")
            val intent = Intent(this, BluetoothForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            if (!isServiceBound) {
                bindService(intent, serviceConnection, Context.BIND_NOT_FOREGROUND)
                isServiceBound = true
                Log.d(TAG, "Bound to foreground service.")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error starting foreground service: ${e.message}", e)
        }
    }

    override fun onStart() {
        super.onStart()
        Log.d(TAG, "onStart: Binding foreground service if permissions granted.")
        if (hasBluetoothConnectPermission() && !isServiceBound) {
            val intent = Intent(this, BluetoothForegroundService::class.java)
            isServiceBound = bindService(intent, serviceConnection, Context.BIND_NOT_FOREGROUND)
            Log.d(TAG, "Bound to service on start: $isServiceBound")
        }
    }

    override fun onStop() {
        super.onStop()
        Log.d(TAG, "onStop: Tearing down active sinks and unbinding service...")
        bluetoothManager?.let { manager ->
            manager.deviceDiscoverySink = null
            manager.connectionStateSink = null
            manager.messageSink = null
            manager.transferProgressSink = null
            Log.d(TAG, "Sinks cleared from manager onStop.")
        }
        if (isServiceBound && bluetoothService != null) {
            unbindService(serviceConnection)
            bluetoothService = null
            isServiceBound = false
            Log.d(TAG, "Unbound service on stop.")
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "configureFlutterEngine: Setting up method and event channels.")

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_DISCOVERY).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    Log.d(TAG, "EVENT_DISCOVERY stream onListen.")
                    deviceDiscoverySink = events
                    bluetoothManager?.deviceDiscoverySink = events
                }

                override fun onCancel(arguments: Any?) {
                    Log.d(TAG, "EVENT_DISCOVERY stream onCancel.")
                    deviceDiscoverySink = null
                    bluetoothManager?.deviceDiscoverySink = null
                }
            }
        )

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CONNECTION).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    Log.d(TAG, "EVENT_CONNECTION stream onListen.")
                    connectionStateSink = events
                    bluetoothManager?.connectionStateSink = events
                }

                override fun onCancel(arguments: Any?) {
                    Log.d(TAG, "EVENT_CONNECTION stream onCancel.")
                    connectionStateSink = null
                    bluetoothManager?.connectionStateSink = null
                }
            }
        )

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_MESSAGES).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    Log.d(TAG, "EVENT_MESSAGES stream onListen.")
                    messageSink = events
                    bluetoothManager?.messageSink = events
                }

                override fun onCancel(arguments: Any?) {
                    Log.d(TAG, "EVENT_MESSAGES stream onCancel.")
                    messageSink = null
                    bluetoothManager?.messageSink = null
                }
            }
        )

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_PROGRESS).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    Log.d(TAG, "EVENT_PROGRESS stream onListen.")
                    transferProgressSink = events
                    bluetoothManager?.transferProgressSink = events
                }

                override fun onCancel(arguments: Any?) {
                    Log.d(TAG, "EVENT_PROGRESS stream onCancel.")
                    transferProgressSink = null
                    bluetoothManager?.transferProgressSink = null
                }
            }
        )
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "MethodChannel call: ${call.method}")
        when (call.method) {
            "startBluetoothService" -> {
                startBluetoothForegroundService()
                result.success(true)
                return
            }
            "checkBluetoothPermission" -> {
                result.success(hasBluetoothConnectPermission())
                return
            }
        }

        val manager = bluetoothManager
        if (manager == null) {
            Log.w(TAG, "Bluetooth Connection Manager is null. Service is starting.")
            result.error("SERVICE_UNAVAILABLE", "Bluetooth background service is starting", null)
            return
        }

        when (call.method) {
            "startDiscovery" -> {
                manager.startDiscovery()
                result.success(true)
            }
            "stopDiscovery" -> {
                manager.stopDiscovery()
                result.success(true)
            }
            "startServer" -> {
                manager.startServer()
                result.success(true)
            }
            "stopServer" -> {
                manager.stopServer()
                result.success(true)
            }
            "connectToDevice" -> {
                val address = call.argument<String>("address")
                if (address != null) {
                    manager.connectToDevice(address)
                    result.success(true)
                } else {
                    result.error("INVALID_ARGUMENT", "Device address is required", null)
                }
            }
            "disconnect" -> {
                val address = call.argument<String>("address")
                if (address != null) {
                    manager.disconnect(address)
                    result.success(true)
                } else {
                    result.error("INVALID_ARGUMENT", "Device address is required", null)
                }
            }
            "disconnectAll" -> {
                manager.disconnectAll()
                result.success(true)
            }
            "sendMessage" -> {
                val address = call.argument<String>("address")
                val messageJson = call.argument<String>("messageJson")
                if (address != null && messageJson != null) {
                    val success = manager.sendMessage(address, messageJson)
                    result.success(success)
                } else {
                    result.error("INVALID_ARGUMENT", "Address and messageJson are required", null)
                }
            }
            "broadcastMessage" -> {
                val messageJson = call.argument<String>("messageJson")
                if (messageJson != null) {
                    manager.broadcastMessage(messageJson)
                    result.success(true)
                } else {
                    result.error("INVALID_ARGUMENT", "messageJson is required", null)
                }
            }
            "sendFile" -> {
                val address = call.argument<String>("address")
                val filePath = call.argument<String>("filePath")
                val fileId = call.argument<String>("fileId")
                val fileName = call.argument<String>("fileName")
                val fileSize = call.argument<Number>("fileSize")?.toLong()
                val senderName = call.argument<String>("senderName")

                if (address != null && filePath != null && fileId != null && fileName != null && fileSize != null && senderName != null) {
                    manager.sendFile(address, filePath, fileId, fileName, fileSize, senderName)
                    result.success(true)
                } else {
                    result.error("INVALID_ARGUMENT", "Missing arguments for sendFile", null)
                }
            }
            "startAudioCall" -> {
                val address = call.argument<String>("address")
                val isVideo = call.argument<Boolean>("isVideo") ?: false
                if (address != null) {
                    manager.startAudioCall(address, isVideo)
                    result.success(true)
                } else {
                    result.error("INVALID_ARGUMENT", "Address is required", null)
                }
            }
            "stopAudioCall" -> {
                manager.stopAudioCall()
                result.success(true)
            }
            "dismissNotification" -> {
                val sessionId = call.argument<String>("sessionId")
                if (sessionId != null) {
                    manager.dismissNotification(sessionId)
                    result.success(true)
                } else {
                    result.error("INVALID_ARGUMENT", "Session ID is required", null)
                }
            }
            "shareFile" -> {
                val filePath = call.argument<String>("filePath")
                val mimeType = call.argument<String>("mimeType") ?: "*/*"
                if (filePath == null) {
                    result.error("INVALID_ARGUMENT", "filePath is required", null)
                    return
                }
                val file = File(filePath)
                if (!file.exists() || !file.isFile) {
                    result.error("FILE_NOT_FOUND", "File does not exist: $filePath", null)
                    return
                }
                try {
                    val uri = FileProvider.getUriForFile(this, "${packageName}.fileprovider", file)
                    val shareIntent = Intent(Intent.ACTION_SEND).apply {
                        type = mimeType
                        putExtra(Intent.EXTRA_STREAM, uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivity(Intent.createChooser(shareIntent, "Share file via"))
                    result.success(true)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to share file: ${e.message}", e)
                    result.error("SHARE_FAILED", "Failed to share file: ${e.message}", null)
                }
            }
            "getMyAddress" -> {
                result.success(manager.getMyAddress(context))
            }
            "setActiveSessionId" -> {
                val sessionId = call.argument<String>("sessionId")
                manager.activeSessionId = sessionId
                result.success(true)
            }
            "getInstalledUpiApps" -> {
                val upiAppsList = mutableListOf<Map<String, String>>()
                try {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse("upi://pay"))
                    val pm = context.packageManager
                    val resolveInfoList = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        pm.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_DEFAULT_ONLY.toLong()))
                    } else {
                        @Suppress("DEPRECATION")
                        pm.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
                    }

                    for (resolveInfo in resolveInfoList) {
                        val packageName = resolveInfo.activityInfo.packageName
                        val appLabel = resolveInfo.loadLabel(pm).toString()
                        upiAppsList.add(mapOf(
                            "packageName" to packageName,
                            "appName" to appLabel
                        ))
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                }
                result.success(upiAppsList)
            }
            "launchUpiPayment" -> {
                val upiUriStr = call.argument<String>("upiUri")
                val packageName = call.argument<String>("packageName")
                if (upiUriStr != null && packageName != null) {
                    try {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(upiUriStr)).apply {
                            setPackage(packageName)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        context.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("LAUNCH_FAILED", "Failed to launch UPI app: ${e.message}", null)
                    }
                } else {
                    result.error("INVALID_ARGUMENT", "upiUri and packageName are required", null)
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }
}
