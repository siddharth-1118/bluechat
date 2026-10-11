package com.example.bluechat.bluechat

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.nio.ByteBuffer
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledThreadPoolExecutor
import java.util.concurrent.TimeUnit
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.CameraCharacteristics
import android.media.ImageReader
import android.media.Image
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import java.io.ByteArrayOutputStream
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.core.app.NotificationCompat

class BluetoothConnectionManager(private val context: Context) {

    private val bluetoothAdapter: BluetoothAdapter? = BluetoothAdapter.getDefaultAdapter()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val threadPool = Executors.newCachedThreadPool()
    private val scheduler = ScheduledThreadPoolExecutor(2)

    // Connection references
    private var acceptThread: AcceptThread? = null
    private val activeConnectThreads = ConcurrentHashMap<String, ConnectThread>()
    private val activeConnections = ConcurrentHashMap<String, ConnectedThread>()
    private val connectingAddresses = ConcurrentHashMap.newKeySet<String>()

    // Voice Calling States
    private var audioRecord: android.media.AudioRecord? = null
    private var audioTrack: android.media.AudioTrack? = null
    private var isCallActive = false
    private var activeCallAddress: String? = null
    private var recordingThread: Thread? = null
    private var echoCanceler: android.media.audiofx.AcousticEchoCanceler? = null
    private var noiseSuppressor: android.media.audiofx.NoiseSuppressor? = null
    private val audioPlaybackQueue = java.util.concurrent.LinkedBlockingQueue<ByteArray>()
    private var audioPlaybackThread: Thread? = null

    // Calling and notification alerts state
    private var ringtone: Ringtone? = null
    private var toneGenerator: ToneGenerator? = null
    private var vibrator: Vibrator? = null

    // Audio manager state caching
    private var oldAudioMode = android.media.AudioManager.MODE_NORMAL
    private var oldIsSpeakerphoneOn = false
    private var isVideoCallActive = false

    // Active session tracking
    var activeSessionId: String? = null

    // Camera fields
    private var cameraDevice: CameraDevice? = null
    private var cameraSession: CameraCaptureSession? = null
    private var imageReader: ImageReader? = null
    private var cameraBackgroundThread: android.os.HandlerThread? = null
    private var cameraHandler: Handler? = null

    // Track active file downloads (FileID -> FileOutputStream)
    private val activeDownloads = ConcurrentHashMap<String, FileOutputStream>()
    private val activeDownloadFiles = ConcurrentHashMap<String, File>()

    init {
        createMessageNotificationChannel()
    }

    private fun createMessageNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "BlueChat Messages"
            val descriptionText = "Notifications for incoming messages"
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel(MSG_CHANNEL_ID, name, importance).apply {
                description = descriptionText
                enableLights(true)
                enableVibration(true)
            }
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun startIncomingCallAlert() {
        try {
            stopAllAlerts()
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ringtone = RingtoneManager.getRingtone(context, uri)
            ringtone?.play()

            vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 1000, 1000), 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(longArrayOf(0, 1000, 1000), 0)
            }
        } catch (e: Exception) {
            Log.e("BlueChat", "Error starting incoming call alert", e)
        }
    }

    private fun startOutgoingCallAlert() {
        try {
            stopAllAlerts()
            toneGenerator = ToneGenerator(AudioManager.STREAM_VOICE_CALL, 80)
            threadPool.execute {
                while (toneGenerator != null) {
                    toneGenerator?.startTone(ToneGenerator.TONE_SUP_RINGTONE, 1000)
                    Thread.sleep(3000)
                }
            }
        } catch (e: Exception) {
            Log.e("BlueChat", "Error starting outgoing call alert", e)
        }
    }

    private fun stopAllAlerts() {
        try {
            ringtone?.stop()
            ringtone = null
            vibrator?.cancel()
            vibrator = null
            toneGenerator?.release()
            toneGenerator = null
        } catch (e: Exception) {
            Log.e("BlueChat", "Error stopping alerts", e)
        }
    }

    private fun isSessionMuted(context: Context, sessionId: String): Boolean {
        val dbFile = context.getDatabasePath("bluechat.db")
        if (!dbFile.exists()) return false
        var muted = false
        try {
            val db = android.database.sqlite.SQLiteDatabase.openDatabase(
                dbFile.absolutePath,
                null,
                android.database.sqlite.SQLiteDatabase.OPEN_READONLY
            )
            val cursor = db.rawQuery("SELECT is_muted FROM sessions WHERE id = ?", arrayOf(sessionId))
            if (cursor.moveToFirst()) {
                muted = cursor.getInt(0) == 1
            }
            cursor.close()
            db.close()
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return muted
    }

    private fun showIncomingMessageNotification(sessionId: String, senderName: String, body: String, isEncrypted: Boolean) {
        if (isSessionMuted(context, sessionId)) return

        val messageText = if (isEncrypted) "[Encrypted Message]" else body

        val notificationIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            sessionId.hashCode(),
            notificationIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, MSG_CHANNEL_ID)
            .setContentTitle(senderName)
            .setContentText(messageText)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(Notification.DEFAULT_ALL)
            .build()

        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(sessionId.hashCode(), notification)
    }

    fun dismissNotification(sessionId: String) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(sessionId.hashCode())
    }

    private fun startCamera() {
        if (cameraDevice != null) return
        
        cameraBackgroundThread = android.os.HandlerThread("CameraBackground").apply { start() }
        cameraHandler = Handler(cameraBackgroundThread!!.looper)

        val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        try {
            var frontCameraId: String? = null
            for (cameraId in cameraManager.cameraIdList) {
                val characteristics = cameraManager.getCameraCharacteristics(cameraId)
                val facing = characteristics.get(android.hardware.camera2.CameraCharacteristics.LENS_FACING)
                if (facing == android.hardware.camera2.CameraCharacteristics.LENS_FACING_FRONT) {
                    frontCameraId = cameraId
                    break
                }
            }
            if (frontCameraId == null && cameraManager.cameraIdList.isNotEmpty()) {
                frontCameraId = cameraManager.cameraIdList[0]
            }

            if (frontCameraId == null) {
                Log.e("BlueChat", "No camera found on this device")
                return
            }

            cameraManager.openCamera(frontCameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    cameraDevice = camera
                    createCameraPreviewSession()
                }

                override fun onDisconnected(camera: CameraDevice) {
                    camera.close()
                    cameraDevice = null
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    camera.close()
                    cameraDevice = null
                }
            }, cameraHandler)
        } catch (e: SecurityException) {
            Log.e("BlueChat", "Camera permission missing", e)
        } catch (e: Exception) {
            Log.e("BlueChat", "Failed to open camera", e)
        }
    }

    private fun createCameraPreviewSession() {
        val device = cameraDevice ?: return
        val width = 320
        val height = 240
        imageReader = ImageReader.newInstance(width, height, ImageFormat.YUV_420_888, 2)
        imageReader?.setOnImageAvailableListener({ reader ->
            val image = reader.acquireLatestImage()
            if (image != null) {
                try {
                    val jpegBytes = processYUVImage(image)
                    if (jpegBytes != null) {
                        sendVideoFrame(jpegBytes, isLocal = true)
                        
                        if (isCallActive && activeCallAddress != null) {
                            val conn = activeConnections[activeCallAddress]
                            conn?.writeFrame(FRAME_TYPE_VIDEO, jpegBytes)
                        }
                    }
                } catch (e: Exception) {
                    Log.e("BlueChat", "Error processing camera frame", e)
                } finally {
                    image.close()
                }
            }
        }, cameraHandler)

        try {
            val surface = imageReader!!.surface
            val builder = device.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                addTarget(surface)
            }

            device.createCaptureSession(listOf(surface), object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    cameraSession = session
                    try {
                        session.setRepeatingRequest(builder.build(), null, cameraHandler)
                    } catch (e: Exception) {
                        Log.e("BlueChat", "Failed to set repeating camera request", e)
                    }
                }

                override fun onConfigureFailed(session: CameraCaptureSession) {
                    Log.e("BlueChat", "Camera configuration failed")
                }
            }, cameraHandler)
        } catch (e: Exception) {
            Log.e("BlueChat", "Failed to create camera session", e)
        }
    }

    private fun stopCamera() {
        try {
            cameraSession?.stopRepeating()
            cameraSession?.close()
            cameraSession = null
        } catch (e: Exception) {}

        cameraDevice?.close()
        cameraDevice = null

        imageReader?.close()
        imageReader = null

        cameraBackgroundThread?.quitSafely()
        try {
            cameraBackgroundThread?.join()
        } catch (e: Exception) {}
        cameraBackgroundThread = null
        cameraHandler = null
    }

    private fun processYUVImage(image: Image): ByteArray? {
        val nv21Bytes = yuv420ToNv21(image) ?: return null
        val out = ByteArrayOutputStream()
        val yuvImage = YuvImage(nv21Bytes, ImageFormat.NV21, image.width, image.height, null)
        yuvImage.compressToJpeg(Rect(0, 0, image.width, image.height), 50, out)
        return out.toByteArray()
    }

    private fun yuv420ToNv21(image: Image): ByteArray? {
        val width = image.width
        val height = image.height
        val ySize = width * height
        val uvSize = width * height / 2
        val nv21 = ByteArray(ySize + uvSize)

        val yBuffer = image.planes[0].buffer
        val uBuffer = image.planes[1].buffer
        val vBuffer = image.planes[2].buffer

        val yRowStride = image.planes[0].rowStride
        val uRowStride = image.planes[1].rowStride
        val vRowStride = image.planes[2].rowStride
        val uPixelStride = image.planes[1].pixelStride
        val vPixelStride = image.planes[2].pixelStride

        var pos = 0
        if (yRowStride == width) {
            yBuffer.get(nv21, 0, ySize)
            pos = ySize
        } else {
            for (row in 0 until height) {
                yBuffer.position(row * yRowStride)
                yBuffer.get(nv21, pos, width)
                pos += width
            }
        }

        val uBytes = ByteArray(uBuffer.remaining())
        val vBytes = ByteArray(vBuffer.remaining())
        uBuffer.get(uBytes)
        vBuffer.get(vBytes)

        var uvPos = ySize
        val numPixels = width * height
        for (i in 0 until numPixels / 4) {
            val vIndex = i * vPixelStride
            val uIndex = i * uPixelStride
            if (vIndex < vBytes.size && uIndex < uBytes.size) {
                nv21[uvPos++] = vBytes[vIndex]
                nv21[uvPos++] = uBytes[uIndex]
            }
        }
        return nv21
    }

    private fun sendVideoFrame(jpegBytes: ByteArray, isLocal: Boolean) {
        if (messageSink != null) {
            sendEvent(messageSink, mapOf(
                "type" to "videoFrame",
                "isLocal" to isLocal,
                "data" to jpegBytes
            ))
        }
    }

    fun isConnected(address: String): Boolean {
        return activeConnections.containsKey(address)
    }

    fun isConnecting(address: String): Boolean {
        return connectingAddresses.contains(address)
    }

    // Event Sinks for streaming to Flutter
    var deviceDiscoverySink: EventChannel.EventSink? = null
    var connectionStateSink: EventChannel.EventSink? = null
    var messageSink: EventChannel.EventSink? = null
    var transferProgressSink: EventChannel.EventSink? = null

    private var isDiscoveryReceiverRegistered = false

    private val discoveryReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                BluetoothDevice.ACTION_FOUND -> {
                    val device: BluetoothDevice? = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                    device?.let {
                        val name = it.name ?: "Unknown Device"
                        val deviceMap = mapOf(
                            "name" to name,
                            "address" to it.address,
                            "bonded" to (it.bondState == BluetoothDevice.BOND_BONDED)
                        )
                        sendEvent(deviceDiscoverySink, mapOf("type" to "deviceFound", "device" to deviceMap))

                        val isSaved = getSavedPeerAddresses(context).contains(it.address)
                        val isBonded = it.bondState == BluetoothDevice.BOND_BONDED
                        val isBlueChatName = name.startsWith("BlueChat", ignoreCase = true)

                        if (isBlueChatName || isBonded || isSaved) {
                            if (!isConnected(it.address) && !isConnecting(it.address)) {
                                Log.d("BlueChat", "Auto-discovered peer: $name (${it.address}) [isBlueChat=$isBlueChatName, isBonded=$isBonded, isSaved=$isSaved]. Connecting...")
                                connectToDevice(it.address)
                            }
                        }
                    }
                }
                BluetoothAdapter.ACTION_DISCOVERY_STARTED -> {
                    sendEvent(deviceDiscoverySink, mapOf("type" to "discoveryStarted"))
                }
                BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                    sendEvent(deviceDiscoverySink, mapOf("type" to "discoveryFinished"))
                }
            }
        }
    }

    fun startDiscovery() {
        try {
            if (!isDiscoveryReceiverRegistered) {
                val filter = IntentFilter().apply {
                    addAction(BluetoothDevice.ACTION_FOUND)
                    addAction(BluetoothAdapter.ACTION_DISCOVERY_STARTED)
                    addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
                }
                context.registerReceiver(discoveryReceiver, filter)
                isDiscoveryReceiverRegistered = true
            }
            bluetoothAdapter?.startDiscovery()
        } catch (e: SecurityException) {
            Log.e("BlueChat", "SecurityException starting discovery: ${e.message}")
        }
    }

    fun stopDiscovery() {
        try {
            bluetoothAdapter?.cancelDiscovery()
            if (isDiscoveryReceiverRegistered) {
                context.unregisterReceiver(discoveryReceiver)
                isDiscoveryReceiverRegistered = false
            }
        } catch (e: Exception) {
            Log.e("BlueChat", "Exception stopping discovery: ${e.message}")
        }
    }

    // --- Server Mode (Host Group) ---
    fun startServer() {
        try {
            val thread = acceptThread
            if (thread != null && thread.isAlive) return
            thread?.cancel()
            acceptThread = AcceptThread().apply { start() }
        } catch (e: Exception) {
            Log.e("BlueChat", "Exception in startServer: ${e.message}")
        }
    }

    fun stopServer() {
        acceptThread?.cancel()
        acceptThread = null
    }

    private inner class AcceptThread : Thread() {
        private var serverSocket: BluetoothServerSocket? = null
        @Volatile var isRunning = true

        init {
            name = "BlueChat-AcceptThread"
        }

        override fun run() {
            while (isRunning) {
                try {
                    Log.d("BlueChat", "Starting listenUsingInsecureRfcommWithServiceRecord on server socket...")
                    serverSocket = bluetoothAdapter?.listenUsingInsecureRfcommWithServiceRecord(NAME, APP_UUID)
                    Log.d("BlueChat", "Server socket listening on SPP UUID...")
                    
                    while (isRunning) {
                        val socket = serverSocket?.accept()
                        socket?.let {
                            val address = it.remoteDevice.address
                            val name = it.remoteDevice.name ?: "Unknown"
                            Log.d("BlueChat", "Accepted incoming socket from $name ($address)")

                            // COLLISION RESOLUTION
                            val myAddr = getMyAddress(context)
                            val isCollision = activeConnections.containsKey(address) || 
                                              connectingAddresses.contains(address) || 
                                              activeConnectThreads.containsKey(address)
                            
                            if (isCollision) {
                                val isInitiator = if (myAddr.isNotEmpty() && address.isNotEmpty()) {
                                    myAddr > address
                                } else {
                                    val localName = bluetoothAdapter?.name ?: ""
                                    val remoteName = name
                                    if (localName != remoteName) {
                                        localName > remoteName
                                    } else {
                                        true
                                    }
                                }

                                if (isInitiator) {
                                    Log.d("BlueChat", "Collision resolved (server-side): We are the initiator (our addr/name is larger). Rejecting incoming socket from $address.")
                                    try { it.close() } catch (e: Exception) {}
                                    return@let // Skip connection setup for this accepted socket
                                } else {
                                    Log.d("BlueChat", "Collision resolved (server-side): We are the receiver (our addr/name is smaller). Keeping incoming socket and closing existing client attempts.")
                                    activeConnectThreads[address]?.cancel()
                                    activeConnections[address]?.cancel()
                                }
                            }

                            val connectedThread = ConnectedThread(it, isIncoming = true)
                            activeConnections[address] = connectedThread
                            threadPool.execute(connectedThread)

                            sendConnectionEvent("connected", address, name)
                            resendPendingMessages(context)
                        }
                    }
                } catch (e: Exception) {
                    Log.e("BlueChat", "Accept server socket error: ${e.message}")
                    try { serverSocket?.close() } catch (ex: Exception) {}
                    if (isRunning) {
                        Thread.sleep(2000) // Sleep before recreating server socket
                    }
                }
            }
        }

        fun cancel() {
            isRunning = false
            try {
                serverSocket?.close()
            } catch (e: IOException) {
                Log.e("BlueChat", "Error closing server socket", e)
            }
        }
    }

    // --- Client Mode (Connect to Host) ---
    fun connectToDevice(address: String) {
        if (connectingAddresses.contains(address) || activeConnections.containsKey(address)) return
        activeConnectThreads[address]?.cancel()

        val device = bluetoothAdapter?.getRemoteDevice(address) ?: return
        connectingAddresses.add(address)
        sendConnectionEvent("connecting", address, device.name ?: "Unknown")

        val thread = ConnectThread(device)
        activeConnectThreads[address] = thread
        thread.start()
    }

    private inner class ConnectThread(private val device: BluetoothDevice) : Thread() {
        private var socket: BluetoothSocket? = null
        @Volatile var isRunning = true

        init {
            name = "BlueChat-Connect-${device.address}"
        }

        override fun run() {
            bluetoothAdapter?.cancelDiscovery()
            var attempt = 0
            val maxAttempts = 3
            var connected = false

            while (attempt < maxAttempts && !connected && isRunning) {
                attempt++
                Log.d("BlueChat", "Connecting to ${device.address}, attempt $attempt of $maxAttempts")
                try {
                    val tempSocket = if (attempt == 1) {
                        device.createInsecureRfcommSocketToServiceRecord(APP_UUID)
                    } else if (attempt == 2) {
                        try {
                            device.createRfcommSocketToServiceRecord(APP_UUID)
                        } catch (e: Exception) {
                            device.createInsecureRfcommSocketToServiceRecord(APP_UUID)
                        }
                    } else {
                        try {
                            val m = device.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
                            m.invoke(device, 1) as BluetoothSocket
                        } catch (ex: Exception) {
                            device.createInsecureRfcommSocketToServiceRecord(APP_UUID)
                        }
                    }
                    socket = tempSocket

                    // Timeout connection task
                    val timeoutTask = scheduler.schedule({
                        try {
                            Log.w("BlueChat", "Connection timeout reached for ${device.address}. Closing temporary socket.")
                            tempSocket.close()
                        } catch (e: Exception) {}
                    }, 10, TimeUnit.SECONDS)

                    tempSocket.connect()
                    timeoutTask.cancel(true)

                    // COLLISION RESOLUTION (after successful connect)
                    val address = device.address
                    val myAddr = getMyAddress(context)
                    val isCollision = activeConnections.containsKey(address)

                    if (isCollision) {
                        val isInitiator = if (myAddr.isNotEmpty() && address.isNotEmpty()) {
                            myAddr > address
                        } else {
                            val localName = bluetoothAdapter?.name ?: ""
                            val remoteName = device.name ?: "Unknown"
                            if (localName != remoteName) {
                                localName > remoteName
                            } else {
                                true
                            }
                        }

                        if (!isInitiator) {
                            Log.d("BlueChat", "Collision resolved (client-side): We are the receiver (our addr/name is smaller). Closing client socket in favor of the accepted socket.")
                            try { tempSocket.close() } catch (e: Exception) {}
                            connected = false
                            break
                        }
                    }

                    connected = true
                    Log.d("BlueChat", "Socket connected successfully (client) to ${device.address}")
                } catch (e: IOException) {
                    Log.e("BlueChat", "Connection attempt $attempt failed to ${device.address}: ${e.message}")
                    try { socket?.close() } catch (ex: Exception) {}
                    if (attempt < maxAttempts && isRunning) {
                        Thread.sleep(2000)
                    }
                }
            }

            activeConnectThreads.remove(device.address)
            connectingAddresses.remove(device.address)

            if (connected && isRunning) {
                socket?.let {
                    val address = device.address
                    val name = device.name ?: "Unknown"
                    val connectedThread = ConnectedThread(it, isIncoming = false)
                    activeConnections[address] = connectedThread
                    threadPool.execute(connectedThread)
                    sendConnectionEvent("connected", address, name)
                    resendPendingMessages(context)
                }
            } else {
                sendConnectionEvent("failed", device.address, device.name ?: "Unknown")
            }
        }

        fun cancel() {
            isRunning = false
            activeConnectThreads.remove(device.address)
            connectingAddresses.remove(device.address)
            try {
                socket?.close()
            } catch (e: IOException) {
                Log.e("BlueChat", "Error closing client socket", e)
            }
        }
    }

    fun disconnect(address: String) {
        Log.d("BlueChat", "Disconnect requested for address: $address")
        activeConnections[address]?.cancel()
        activeConnections.remove(address)
        sendConnectionEvent("disconnected", address, "")
    }

    fun disconnectAll() {
        Log.d("BlueChat", "Disconnect all connections requested.")
        stopDiscovery()
        activeConnections.keys.forEach { address ->
            disconnect(address)
        }
    }

    // --- Data Transmission Outgoing Frame Wrapper ---
    private inner class OutgoingFrame(
        val type: Byte,
        val data: ByteArray,
        val messageId: String? = null,
        val sessionId: String? = null
    )

    private inner class ConnectedThread(private val socket: BluetoothSocket, val isIncoming: Boolean) : Runnable {
        private val inputStream: InputStream = socket.inputStream
        private val outputStream: OutputStream = socket.outputStream
        val deviceAddress: String = socket.remoteDevice.address
        val deviceName: String = socket.remoteDevice.name ?: "Unknown"

        @Volatile var isRunning = true
            private set

        val outgoingQueue = java.util.concurrent.LinkedBlockingQueue<OutgoingFrame>()
        private var writerThread: Thread? = null

        override fun run() {
            val directionStr = if (isIncoming) "INCOMING (Server)" else "OUTGOING (Client)"
            Log.d("BlueChat", "ConnectedThread started. Direction: $directionStr, Peer: $deviceName ($deviceAddress)")

            // Outgoing Write Loop Thread
            writerThread = Thread {
                Log.d("BlueChat", "Writer Thread running for $deviceAddress ($directionStr)")
                while (isRunning && socket.isConnected) {
                    try {
                        val frame = outgoingQueue.take()
                        var success = false
                        var attempts = 0
                        val maxAttempts = 3

                        while (attempts < maxAttempts && !success && isRunning && socket.isConnected) {
                            attempts++
                            try {
                                val header = ByteBuffer.allocate(5)
                                    .putInt(frame.data.size)
                                    .put(frame.type)
                                    .array()

                                synchronized(outputStream) {
                                    outputStream.write(header)
                                    outputStream.write(frame.data)
                                    outputStream.flush()
                                }
                                success = true
                                Log.d("BlueChat", "Bytes written: ${header.size + frame.data.size} bytes. Msg sent (type=${frame.type}) to $deviceAddress. Direction: $directionStr")
                            } catch (e: IOException) {
                                Log.e("BlueChat", "Write attempt $attempts failed to $deviceAddress: ${e.message}")
                                if (attempts < maxAttempts && isRunning && socket.isConnected) {
                                    Thread.sleep(1000)
                                } else {
                                    throw e
                                }
                            }
                        }

                        // Emit success/failure triggers to Flutter
                        if (frame.messageId != null && frame.sessionId != null) {
                            mainHandler.post {
                                sendEvent(messageSink, mapOf(
                                    "type" to if (success) "sendSuccess" else "sendFailure",
                                    "messageId" to frame.messageId,
                                    "sessionId" to frame.sessionId
                                ))
                            }
                        }
                    } catch (e: InterruptedException) {
                        break
                    } catch (e: IOException) {
                        Log.e("BlueChat", "Write thread fatal exception: ${e.message}")
                        closeConnection()
                        break
                    }
                }
                Log.d("BlueChat", "Writer Thread stopped for $deviceAddress ($directionStr)")
            }.apply {
                name = "BlueChat-Writer-$deviceAddress"
                start()
            }

            // Handshake info: Send local address configuration to peer
            val sysMsg = JSONObject().apply {
                put("type", "sys_your_address")
                put("address", deviceAddress)
            }
            writeFrame(FRAME_TYPE_TEXT, sysMsg.toString().toByteArray(Charsets.UTF_8))

            // Continuous incoming Read Loop
            val headerBuffer = ByteArray(5)
            while (isRunning && socket.isConnected) {
                try {
                    if (!readExactly(inputStream, headerBuffer)) {
                        Log.w("BlueChat", "Read error: failed to pull header from $deviceAddress. Disconnecting.")
                        break
                    }
                    val length = ByteBuffer.wrap(headerBuffer, 0, 4).int
                    val type = headerBuffer[4]

                    if (length < 0 || length > 10 * 1024 * 1024) {
                        Log.e("BlueChat", "Read error: Invalid payload size $length")
                        break
                    }

                    val payload = ByteArray(length)
                    if (!readExactly(inputStream, payload)) {
                        Log.w("BlueChat", "Read error: failed to pull payload of size $length from $deviceAddress")
                        break
                    }

                    Log.d("BlueChat", "Bytes read: ${headerBuffer.size + payload.size} bytes. Msg received (type=$type) from $deviceAddress. Direction: $directionStr")

                    when (type) {
                        FRAME_TYPE_TEXT, FRAME_TYPE_FILE_METADATA -> {
                            val jsonString = String(payload, Charsets.UTF_8)
                            handleJsonMessage(deviceAddress, jsonString)

                            // Send delivery ACK back to original sender
                            try {
                                val json = JSONObject(jsonString)
                                val msgId = json.optString("id")
                                val jsonType = json.optString("type")
                                if (msgId.isNotEmpty() && jsonType != "sys_your_address" && jsonType != "mesh_delivered") {
                                    sendDeliveryAck(msgId)
                                }
                            } catch (e: Exception) {
                                Log.e("BlueChat", "Error parsing incoming JSON for ACK: ${e.message}")
                            }
                        }
                        FRAME_TYPE_FILE_CHUNK -> {
                            handleBinaryChunk(payload)
                        }
                        FRAME_TYPE_ACK -> {
                            val ackMsgId = String(payload, Charsets.UTF_8)
                            Log.d("BlueChat", "Received delivery ACK for messageId: $ackMsgId from $deviceAddress")
                            updateMessageStatusInDb(context, ackMsgId, "delivered")
                            mainHandler.post {
                                sendEvent(messageSink, mapOf(
                                    "type" to "messageStatusChanged",
                                    "messageId" to ackMsgId,
                                    "sessionId" to deviceAddress,
                                    "status" to "delivered"
                                ))
                            }
                        }
                        FRAME_TYPE_AUDIO -> {
                            if (isCallActive && deviceAddress == activeCallAddress) {
                                if (audioPlaybackQueue.size > 10) {
                                    audioPlaybackQueue.clear()
                                }
                                audioPlaybackQueue.offer(payload)
                            }
                        }
                        FRAME_TYPE_VIDEO -> {
                            if (isCallActive && deviceAddress == activeCallAddress) {
                                sendVideoFrame(payload, isLocal = false)
                            }
                        }
                    }
                } catch (e: IOException) {
                    Log.e("BlueChat", "Read Thread exception: ${e.message}")
                    break
                }
            }
            closeConnection()
        }

        fun writeFrame(type: Byte, data: ByteArray, messageId: String? = null, sessionId: String? = null): Boolean {
            if (!isRunning) return false

            if (outgoingQueue.size > 15) {
                outgoingQueue.clear()
            } else if (outgoingQueue.size > 8) {
                val iterator = outgoingQueue.iterator()
                while (iterator.hasNext()) {
                    if (iterator.next().type == FRAME_TYPE_VIDEO) {
                        iterator.remove()
                    }
                }
            }

            if (type == FRAME_TYPE_VIDEO) {
                var videoCount = 0
                for (frame in outgoingQueue) {
                    if (frame.type == FRAME_TYPE_VIDEO) videoCount++
                }
                if (videoCount > 0) return false
            }

            outgoingQueue.offer(OutgoingFrame(type, data, messageId, sessionId))
            return true
        }

        fun sendDeliveryAck(msgId: String) {
            val ackData = msgId.toByteArray(Charsets.UTF_8)
            writeFrame(FRAME_TYPE_ACK, ackData)
        }

        private fun closeConnection() {
            if (!isRunning) return
            isRunning = false
            writerThread?.interrupt()
            writerThread = null
            outgoingQueue.clear()
            try {
                socket.close()
            } catch (e: Exception) {}

            activeConnections.remove(deviceAddress)
            sendConnectionEvent("disconnected", deviceAddress, deviceName)
        }

        fun cancel() {
            closeConnection()
        }
    }

    private fun readExactly(stream: InputStream, buffer: ByteArray): Boolean {
        var totalRead = 0
        while (totalRead < buffer.size) {
            val read = stream.read(buffer, totalRead, buffer.size - totalRead)
            if (read == -1) return false
            totalRead += read
        }
        return true
    }

    // --- Message Send Logic ---
    fun sendMessage(address: String, messageJson: String): Boolean {
        Log.d("BlueChat", "Sending message to $address: $messageJson")
        var messageId: String? = null
        try {
            val json = JSONObject(messageJson)
            messageId = json.optString("id")
            val type = json.optString("type")
            if (type == "call_invite") {
                startOutgoingCallAlert()
            } else if (type == "call_decline" || type == "call_hangup") {
                stopAllAlerts()
            }
        } catch (e: Exception) {
            Log.e("BlueChat", "Error parsing outgoing message JSON for calls", e)
        }

        val data = messageJson.toByteArray(Charsets.UTF_8)
        val conn = activeConnections[address]
        if (conn != null) {
            return conn.writeFrame(FRAME_TYPE_TEXT, data, messageId, address)
        }

        // Flooding/Forwarding fallback search
        var sent = false
        activeConnections.forEach { (peerAddress, peerConn) ->
            if (peerAddress != address) {
                if (peerConn.writeFrame(FRAME_TYPE_TEXT, data, messageId, address)) {
                    sent = true
                }
            }
        }
        return sent
    }

    fun broadcastMessage(messageJson: String) {
        Log.d("BlueChat", "Broadcasting message: $messageJson")
        var messageId: String? = null
        try {
            val json = JSONObject(messageJson)
            messageId = json.optString("id")
        } catch (e: Exception) {}

        val data = messageJson.toByteArray(Charsets.UTF_8)
        activeConnections.forEach { (_, conn) ->
            conn.writeFrame(FRAME_TYPE_TEXT, data, messageId, "group_chat")
        }
    }

    // --- File Transmission Logic ---
    fun sendFile(address: String, filePath: String, fileId: String, fileName: String, fileSize: Long, senderName: String) {
        threadPool.execute {
            val file = File(filePath)
            if (!file.exists()) {
                sendProgressUpdate(fileId, 0, fileSize, 0, "failed", "File does not exist")
                return@execute
            }

            val conn = activeConnections[address]
            if (conn == null) {
                sendProgressUpdate(fileId, 0, fileSize, 0, "failed", "Device not connected")
                return@execute
            }

            // 1. Send file_start JSON notification
            val startJson = JSONObject().apply {
                put("type", "file_start")
                put("fileId", fileId)
                put("fileName", fileName)
                put("fileSize", fileSize)
                put("sender", senderName)
                put("sessionId", address)
                put("recipientAddress", address)
            }
            if (!conn.writeFrame(FRAME_TYPE_FILE_METADATA, startJson.toString().toByteArray(Charsets.UTF_8), fileId, address)) {
                sendProgressUpdate(fileId, 0, fileSize, 0, "failed", "Failed to start transfer")
                return@execute
            }

            // 2. Read file in chunks and send
            val buffer = ByteArray(32 * 1024) // 32KB chunks
            var bytesSent: Long = 0
            var speedBytes = 0
            var speedLastTime = System.currentTimeMillis()
            var speedRate = 0L

            file.inputStream().use { input ->
                while (true) {
                    val read = input.read(buffer)
                    if (read == -1) break

                    val fileIdBytes = fileId.padEnd(36).toByteArray(Charsets.UTF_8)
                    val chunkPayload = ByteBuffer.allocate(36 + 4 + read)
                        .put(fileIdBytes)
                        .putInt(read)
                        .put(buffer, 0, read)
                        .array()

                    if (!conn.writeFrame(FRAME_TYPE_FILE_CHUNK, chunkPayload)) {
                        sendProgressUpdate(fileId, bytesSent, fileSize, 0, "failed", "Failed to send chunk")
                        return@use
                    }

                    bytesSent += read
                    speedBytes += read

                    val now = System.currentTimeMillis()
                    val timeDelta = now - speedLastTime
                    if (timeDelta >= 500) {
                        speedRate = (speedBytes * 1000L) / timeDelta
                        speedBytes = 0
                        speedLastTime = now
                    }

                    sendProgressUpdate(fileId, bytesSent, fileSize, speedRate, "transferring", "")
                }
            }

            // 3. Send file_end JSON notification
            val endJson = JSONObject().apply {
                put("type", "file_end")
                put("fileId", fileId)
                put("fileName", fileName)
                put("sender", senderName)
                put("sessionId", address)
                put("recipientAddress", address)
            }
            conn.writeFrame(FRAME_TYPE_FILE_METADATA, endJson.toString().toByteArray(Charsets.UTF_8), fileId, address)
            sendProgressUpdate(fileId, fileSize, fileSize, 0, "success", "")
        }
    }

    private fun isPhotoFile(fileName: String): Boolean {
        val ext = fileName.substringAfterLast('.', "").lowercase()
        return ext == "jpg" || ext == "jpeg" || ext == "png" || ext == "gif" || ext == "webp" || ext == "bmp"
    }

    private fun isVideoFile(fileName: String): Boolean {
        val ext = fileName.substringAfterLast('.', "").lowercase()
        return ext == "mp4" || ext == "mov" || ext == "avi" || ext == "mkv" || ext == "webm" || ext == "3gp"
    }

    // --- Message Receivers & Parsing ---
    private fun handleJsonMessage(fromAddress: String, jsonString: String) {
        val json = JSONObject(jsonString)
        val type = json.optString("type")

        when (type) {
            "file_start" -> {
                val fileId = json.getString("fileId")
                val fileName = json.getString("fileName")
                val fileSize = json.getLong("fileSize")
                val sender = json.getString("sender")

                val dir = File(context.getExternalFilesDir(null), "BlueChat")
                if (!dir.exists()) {
                    dir.mkdirs()
                }
                val destFile = File(dir, fileName)
                try {
                    val outStream = FileOutputStream(destFile)
                    activeDownloads[fileId] = outStream
                    activeDownloadFiles[fileId] = destFile

                    sendProgressUpdate(fileId, 0, fileSize, 0, "transferring", "")
                } catch (e: IOException) {
                    sendProgressUpdate(fileId, 0, fileSize, 0, "failed", "Failed to create local file: ${e.message}")
                }
            }
            "file_end" -> {
                val fileId = json.getString("fileId")
                val fileName = json.getString("fileName")
                val sender = json.optString("sender", "Peer")
                val sessionId = json.optString("sessionId", fromAddress)
                val outStream = activeDownloads.remove(fileId)
                val file = activeDownloadFiles.remove(fileId)
                try {
                    outStream?.close()
                } catch (e: Exception) {}

                if (file != null && file.exists()) {
                    if (messageSink != null) {
                        sendProgressUpdate(fileId, file.length(), file.length(), 0, "success", file.absolutePath)
                        val messageJson = JSONObject().apply {
                            put("id", fileId)
                            put("sessionId", sessionId)
                            put("senderAddress", fromAddress)
                            put("senderName", sender)
                            put("body", "Shared file: ${file.name}")
                            put("type", "file")
                            put("filePath", file.absolutePath)
                            put("fileSize", file.length())
                            put("timestamp", System.currentTimeMillis())
                        }
                        sendEvent(messageSink, mapOf("type" to "message", "message" to messageJson.toString()))

                        if (activeSessionId != sessionId) {
                            val notifBody = if (isPhotoFile(file.name)) {
                                "sends you a photo"
                            } else if (isVideoFile(file.name)) {
                                "shared the video"
                            } else {
                                "shared a file: ${file.name}"
                            }
                            showIncomingMessageNotification(sessionId, sender, notifBody, false)
                        }
                    } else {
                        val messageJson = JSONObject().apply {
                            put("id", fileId)
                            put("sessionId", sessionId)
                            put("senderName", sender)
                            put("body", "Shared file: ${file.name}")
                            put("type", "file")
                            put("timestamp", System.currentTimeMillis())
                        }
                        saveMessageToDb(context, fromAddress, messageJson.toString())
                        saveFilePathToDb(context, fileId, file.absolutePath)

                        val notifBody = if (isPhotoFile(file.name)) {
                            "sends you a photo"
                        } else if (isVideoFile(file.name)) {
                            "shared the video"
                        } else {
                            "shared a file: ${file.name}"
                        }
                        showIncomingMessageNotification(sessionId, sender, notifBody, false)
                    }
                } else {
                    sendProgressUpdate(fileId, 0, 0, 0, "failed", "File not saved correctly")
                }
            }
            else -> {
                val msgId = json.optString("id")
                val recipientAddress = json.optString("recipientAddress", json.optString("sessionId"))
                var senderAddress = json.optString("senderAddress")
                if (senderAddress.isEmpty() || !senderAddress.contains(":") || senderAddress.startsWith("swmp_")) {
                    senderAddress = fromAddress
                }
                val hopCount = json.optInt("hopCount", 0)
                val maxHops = json.optInt("maxHops", 200)

                val jsonType = json.optString("type")
                if (jsonType == "typing") {
                    if (messageSink != null) {
                        sendEvent(messageSink, mapOf(
                            "type" to "message",
                            "message" to jsonString,
                            "senderAddress" to senderAddress
                        ))
                    }
                    return
                }
                if (jsonType == "sys_your_address") {
                    val myAddr = json.getString("address")
                    saveMyAddress(context, myAddr)
                    if (messageSink != null) {
                        sendEvent(messageSink, mapOf(
                            "type" to "myAddressUpdated",
                            "address" to myAddr
                        ))
                    }
                    return
                }

                if (jsonType == "call_invite") {
                    startIncomingCallAlert()
                    try {
                        val launchIntent = Intent(context, MainActivity::class.java).apply {
                            action = Intent.ACTION_MAIN
                            addCategory(Intent.CATEGORY_LAUNCHER)
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP
                        }
                        context.startActivity(launchIntent)
                    } catch (e: Exception) {
                        Log.e("BlueChat", "Error launching MainActivity on call invite", e)
                    }
                } else if (jsonType == "call_accept") {
                    stopAllAlerts()
                } else if (jsonType == "call_decline" || jsonType == "call_hangup") {
                    stopAllAlerts()
                    stopAudioCall()
                }

                if (msgId.isNotEmpty()) {
                    if (hasSeenMessage(context, msgId)) return
                    markMessageAsSeen(context, msgId)
                }

                val myAddress = getMyAddress(context)
                val isForMe = recipientAddress == "group_chat" ||
                              recipientAddress.startsWith("group_") ||
                              (myAddress.isNotEmpty() && recipientAddress.equals(myAddress, ignoreCase = true)) ||
                              (recipientAddress.equals(fromAddress, ignoreCase = true)) ||
                              (myAddress.isEmpty())

                if (isForMe) {
                    val isGroup = recipientAddress == "group_chat" || recipientAddress.startsWith("group_")
                    val sessionId = if (isGroup) recipientAddress else senderAddress

                    if (jsonType == "mesh_delivered") {
                        val targetId = json.optString("targetMessageId")
                        if (targetId.isNotEmpty()) {
                            updateMessageStatusInDb(context, targetId, "delivered")
                            if (messageSink != null) {
                                sendEvent(messageSink, mapOf(
                                    "type" to "messageStatusChanged",
                                    "messageId" to targetId,
                                    "sessionId" to sessionId,
                                    "status" to "delivered"
                                ))
                            }
                        }
                        return
                    }

                    if (messageSink != null) {
                        sendEvent(messageSink, mapOf(
                            "type" to "message",
                            "message" to jsonString,
                            "senderAddress" to senderAddress
                        ))

                        if (activeSessionId != sessionId &&
                            jsonType != "dh_request" && jsonType != "dh_response" &&
                            jsonType != "call_invite" && jsonType != "call_accept" &&
                            jsonType != "call_decline" && jsonType != "call_hangup") {
                            val sender = json.optString("senderName", "Peer")
                            val body = json.optString("body")
                            val isEncrypted = jsonType == "encrypted_text"
                            showIncomingMessageNotification(sessionId, sender, body, isEncrypted)
                        }
                    } else {
                        saveMessageToDb(context, senderAddress, jsonString)
                        
                        if (jsonType != "dh_request" && jsonType != "dh_response" &&
                            jsonType != "call_invite" && jsonType != "call_accept" &&
                            jsonType != "call_decline" && jsonType != "call_hangup") {
                            val sender = json.optString("senderName", "Peer")
                            val body = json.optString("body")
                            val isEncrypted = jsonType == "encrypted_text"
                            showIncomingMessageNotification(sessionId, sender, body, isEncrypted)
                        }
                    }

                    if (!isGroup && msgId.isNotEmpty() &&
                        jsonType != "dh_request" && jsonType != "dh_response" &&
                        jsonType != "call_invite" && jsonType != "call_accept" &&
                        jsonType != "call_decline" && jsonType != "call_hangup" &&
                        jsonType != "sys_your_address") {
                        
                        val myAddr = getMyAddress(context)
                        if (myAddr.isNotEmpty() && senderAddress.isNotEmpty()) {
                            val ackJson = JSONObject().apply {
                                put("id", java.util.UUID.randomUUID().toString())
                                put("type", "mesh_delivered")
                                put("targetMessageId", msgId)
                                put("senderAddress", myAddr)
                                put("recipientAddress", senderAddress)
                                put("timestamp", System.currentTimeMillis())
                                put("hopCount", 0)
                                put("maxHops", 200)
                            }.toString()
                            
                            sendMessage(senderAddress, ackJson)
                        }
                    }
                }

                // Mesh Forwarding Loop
                if (hopCount < maxHops) {
                    val nextHopJson = JSONObject(jsonString).apply {
                        put("hopCount", hopCount + 1)
                        put("senderAddress", senderAddress)
                    }.toString()
                    val nextHopData = nextHopJson.toByteArray(Charsets.UTF_8)

                    if (recipientAddress == "group_chat" || recipientAddress.startsWith("group_")) {
                        activeConnections.forEach { (address, conn) ->
                            if (address != fromAddress) {
                                conn.writeFrame(FRAME_TYPE_TEXT, nextHopData)
                            }
                        }
                    } else if (recipientAddress != myAddress) {
                        val targetConn = activeConnections[recipientAddress]
                        val deliveredDirectly = if (targetConn != null) {
                            targetConn.writeFrame(FRAME_TYPE_TEXT, nextHopData)
                        } else {
                            false
                        }

                        if (deliveredDirectly) {
                            deleteTransitMessage(context, msgId)
                        } else {
                            saveTransitMessage(context, msgId, recipientAddress, nextHopJson)
                            activeConnections.forEach { (address, conn) ->
                                if (address != fromAddress) {
                                    conn.writeFrame(FRAME_TYPE_TEXT, nextHopData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private fun handleBinaryChunk(payload: ByteArray) {
        if (payload.size < 40) return
        val fileIdBytes = payload.sliceArray(0 until 36)
        val fileId = String(fileIdBytes, Charsets.UTF_8).trim()
        val chunkLength = ByteBuffer.wrap(payload, 36, 4).int
        val chunkData = payload.sliceArray(40 until (40 + chunkLength))

        val outputStream = activeDownloads[fileId]
        if (outputStream != null) {
            try {
                outputStream.write(chunkData)
                outputStream.flush()
            } catch (e: IOException) {
                activeDownloads.remove(fileId)
                try { outputStream.close() } catch (ex: Exception) {}
                sendProgressUpdate(fileId, 0, 0, 0, "failed", "Writing error: ${e.message}")
            }
        }
    }

    // --- Helper Channels ---
    private fun sendEvent(sink: EventChannel.EventSink?, event: Map<String, Any>) {
        mainHandler.post {
            try {
                sink?.success(event)
            } catch (e: Exception) {}
        }
    }

    private fun sendConnectionEvent(state: String, address: String, name: String) {
        sendEvent(connectionStateSink, mapOf("state" to state, "address" to address, "name" to name))
    }

    private fun sendProgressUpdate(fileId: String, progress: Long, total: Long, speed: Long, status: String, errorOrPath: String) {
        sendEvent(transferProgressSink, mapOf(
            "fileId" to fileId,
            "progress" to progress,
            "total" to total,
            "speed" to speed,
            "status" to status,
            "errorOrPath" to errorOrPath
        ))
    }

    fun getSavedPeerAddresses(context: Context): List<String> {
        val dbFile = context.getDatabasePath("bluechat.db")
        if (!dbFile.exists()) return emptyList()
        val addresses = mutableListOf<String>()
        try {
            val db = android.database.sqlite.SQLiteDatabase.openDatabase(
                dbFile.absolutePath,
                null,
                android.database.sqlite.SQLiteDatabase.OPEN_READONLY
            )
            val cursor = db.rawQuery("SELECT address FROM peers", null)
            while (cursor.moveToNext()) {
                addresses.add(cursor.getString(0))
            }
            cursor.close()
            db.close()
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return addresses
    }

    fun saveMessageToDb(context: Context, fromAddress: String, jsonString: String) {
        val dbFile = context.getDatabasePath("bluechat.db")
        if (!dbFile.exists()) return
        try {
            val json = JSONObject(jsonString)
            val id = json.getString("id")
            val senderName = json.getString("senderName")
            val body = json.getString("body")
            val type = json.getString("type")
            val timestamp = json.getLong("timestamp")
            
            val db = android.database.sqlite.SQLiteDatabase.openDatabase(
                dbFile.absolutePath,
                null,
                android.database.sqlite.SQLiteDatabase.OPEN_READWRITE
            )
            val values = android.content.ContentValues().apply {
                put("id", id)
                put("session_id", fromAddress)
                put("sender_name", senderName)
                put("sender_address", fromAddress)
                put("body", body)
                put("status", "received")
                put("timestamp", timestamp)
                put("type", type)
            }
            db.insertWithOnConflict("messages", null, values, android.database.sqlite.SQLiteDatabase.CONFLICT_REPLACE)
            db.close()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun saveFilePathToDb(context: Context, fileId: String, filePath: String) {
        val dbFile = context.getDatabasePath("bluechat.db")
        if (!dbFile.exists()) return
        try {
            val db = android.database.sqlite.SQLiteDatabase.openDatabase(
                dbFile.absolutePath,
                null,
                android.database.sqlite.SQLiteDatabase.OPEN_READWRITE
            )
            val values = android.content.ContentValues().apply {
                put("file_path", filePath)
            }
            db.update("messages", values, "id = ?", arrayOf(fileId))
            db.close()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun updateMessageStatusInDb(context: Context, msgId: String, status: String) {
        val dbFile = context.getDatabasePath("bluechat.db")
        if (!dbFile.exists()) return
        try {
            val db = android.database.sqlite.SQLiteDatabase.openDatabase(
                dbFile.absolutePath,
                null,
                android.database.sqlite.SQLiteDatabase.OPEN_READWRITE
            )
            val values = android.content.ContentValues().apply {
                put("status", status)
            }
            db.update("messages", values, "id = ?", arrayOf(msgId))
            db.close()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun getMyAddress(context: Context): String {
        val prefs = context.getSharedPreferences("BlueChatPrefs", Context.MODE_PRIVATE)
        return prefs.getString("my_address", "") ?: ""
    }

    fun saveMyAddress(context: Context, address: String) {
        val prefs = context.getSharedPreferences("BlueChatPrefs", Context.MODE_PRIVATE)
        prefs.edit().putString("my_address", address).apply()
    }

    fun hasSeenMessage(context: Context, msgId: String): Boolean {
        val dbFile = context.getDatabasePath("bluechat.db")
        if (!dbFile.exists()) return false
        var seen = false
        try {
            val db = android.database.sqlite.SQLiteDatabase.openDatabase(
                dbFile.absolutePath,
                null,
                android.database.sqlite.SQLiteDatabase.OPEN_READWRITE
            )
            db.execSQL("CREATE TABLE IF NOT EXISTS seen_messages (id TEXT PRIMARY KEY, timestamp INTEGER)")
            val cursor = db.rawQuery("SELECT 1 FROM seen_messages WHERE id = ?", arrayOf(msgId))
            seen = cursor.count > 0
            cursor.close()
            db.close()
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return seen
    }

    fun markMessageAsSeen(context: Context, msgId: String) {
        val dbFile = context.getDatabasePath("bluechat.db")
        if (!dbFile.exists()) return
        try {
            val db = android.database.sqlite.SQLiteDatabase.openDatabase(
                dbFile.absolutePath,
                null,
                android.database.sqlite.SQLiteDatabase.OPEN_READWRITE
            )
            db.execSQL("CREATE TABLE IF NOT EXISTS seen_messages (id TEXT PRIMARY KEY, timestamp INTEGER)")
            val values = android.content.ContentValues().apply {
                put("id", msgId)
                put("timestamp", System.currentTimeMillis())
            }
            db.insertWithOnConflict("seen_messages", null, values, android.database.sqlite.SQLiteDatabase.CONFLICT_REPLACE)
            db.close()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun saveTransitMessage(context: Context, id: String, recipientAddress: String, rawJson: String) {
        val dbFile = context.getDatabasePath("bluechat.db")
        if (!dbFile.exists()) return
        try {
            val db = android.database.sqlite.SQLiteDatabase.openDatabase(
                dbFile.absolutePath,
                null,
                android.database.sqlite.SQLiteDatabase.OPEN_READWRITE
            )
            db.execSQL("CREATE TABLE IF NOT EXISTS transit_messages (id TEXT PRIMARY KEY, recipient_address TEXT, raw_json TEXT, timestamp INTEGER)")
            val values = android.content.ContentValues().apply {
                put("id", id)
                put("recipient_address", recipientAddress)
                put("raw_json", rawJson)
                put("timestamp", System.currentTimeMillis())
            }
            db.insertWithOnConflict("transit_messages", null, values, android.database.sqlite.SQLiteDatabase.CONFLICT_REPLACE)
            db.close()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun deleteTransitMessage(context: Context, id: String) {
        val dbFile = context.getDatabasePath("bluechat.db")
        if (!dbFile.exists()) return
        try {
            val db = android.database.sqlite.SQLiteDatabase.openDatabase(
                dbFile.absolutePath,
                null,
                android.database.sqlite.SQLiteDatabase.OPEN_READWRITE
            )
            db.delete("transit_messages", "id = ?", arrayOf(id))
            db.close()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun resendPendingMessages(context: Context) {
        val dbFile = context.getDatabasePath("bluechat.db")
        if (!dbFile.exists()) return
        try {
            val db = android.database.sqlite.SQLiteDatabase.openDatabase(
                dbFile.absolutePath,
                null,
                android.database.sqlite.SQLiteDatabase.OPEN_READWRITE
            )
            
            db.execSQL("CREATE TABLE IF NOT EXISTS messages (id TEXT PRIMARY KEY, session_id TEXT, sender_name TEXT, sender_address TEXT, body TEXT, status TEXT, timestamp INTEGER, type TEXT, file_path TEXT, file_size INTEGER, file_name TEXT)")
            val cursor = db.rawQuery("SELECT id, session_id, sender_name, sender_address, body, status, timestamp, type, file_path, file_size, file_name FROM messages WHERE status = 'sending'", null)
            
            val pendingList = mutableListOf<JSONObject>()
            val pendingFilesList = mutableListOf<Map<String, Any>>()
            
            while (cursor.moveToNext()) {
                val id = cursor.getString(0)
                val sessionId = cursor.getString(1)
                val senderName = cursor.getString(2)
                val type = cursor.getString(7)
                val senderAddress = cursor.getString(3)
                
                if (type == "file") {
                    val filePath = cursor.getString(8) ?: ""
                    val fileSize = cursor.getLong(9)
                    val fileName = cursor.getString(10) ?: ""
                    if (filePath.isNotEmpty()) {
                        pendingFilesList.add(mapOf(
                            "id" to id,
                            "sessionId" to sessionId,
                            "filePath" to filePath,
                            "fileSize" to fileSize,
                            "fileName" to fileName,
                            "senderName" to senderName
                        ))
                    }
                } else {
                    val json = JSONObject().apply {
                        put("id", id)
                        put("sessionId", sessionId)
                        put("recipientAddress", sessionId)
                        put("senderName", senderName)
                        put("senderAddress", senderAddress)
                        put("body", cursor.getString(4))
                        put("type", type)
                        put("timestamp", cursor.getLong(6))
                        put("hopCount", 0)
                        put("maxHops", 200)
                    }
                    pendingList.add(json)
                }
            }
            cursor.close()

            for (msgJson in pendingList) {
                val address = msgJson.getString("sessionId")
                val success = sendMessage(address, msgJson.toString())
                if (success) {
                    val msgId = msgJson.getString("id")
                    val values = android.content.ContentValues().apply {
                        put("status", "sent")
                    }
                    db.update("messages", values, "id = ?", arrayOf(msgId))
                    if (messageSink != null) {
                        sendEvent(messageSink, mapOf(
                            "type" to "messageStatusChanged",
                            "messageId" to msgId,
                            "sessionId" to address,
                            "status" to "sent"
                        ))
                    }
                }
            }

            for (fileInfo in pendingFilesList) {
                val id = fileInfo["id"] as String
                val sessionId = fileInfo["sessionId"] as String
                val filePath = fileInfo["filePath"] as String
                val fileSize = fileInfo["fileSize"] as Long
                val fileName = fileInfo["fileName"] as String
                val senderName = fileInfo["senderName"] as String
                
                if (activeConnections.containsKey(sessionId)) {
                    sendFile(sessionId, filePath, id, fileName, fileSize, senderName)
                }
            }

            db.execSQL("CREATE TABLE IF NOT EXISTS transit_messages (id TEXT PRIMARY KEY, recipient_address TEXT, raw_json TEXT, timestamp INTEGER)")
            val transitCursor = db.rawQuery("SELECT id, recipient_address, raw_json FROM transit_messages", null)
            val transitList = mutableListOf<Triple<String, String, String>>()
            while (transitCursor.moveToNext()) {
                transitList.add(Triple(transitCursor.getString(0), transitCursor.getString(1), transitCursor.getString(2)))
            }
            transitCursor.close()

            for (transit in transitList) {
                val id = transit.first
                val recipientAddress = transit.second
                val rawJson = transit.third
                
                if (activeConnections.containsKey(recipientAddress)) {
                    val success = sendMessage(recipientAddress, rawJson)
                    if (success) {
                        db.delete("transit_messages", "id = ?", arrayOf(id))
                    }
                } else {
                    sendMessage(recipientAddress, rawJson)
                }
            }

            val twoDaysAgo = System.currentTimeMillis() - 48L * 60 * 60 * 1000
            db.delete("transit_messages", "timestamp < ?", arrayOf(twoDaysAgo.toString()))
            db.close()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun startAudioCall(address: String, isVideo: Boolean) {
        if (isCallActive) return
        stopAllAlerts()

        (context as? BluetoothForegroundService)?.updateForegroundTypes(hasMic = true, hasCamera = isVideo)

        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
            oldAudioMode = audioManager.mode
            oldIsSpeakerphoneOn = audioManager.isSpeakerphoneOn
            
            audioManager.mode = android.media.AudioManager.MODE_IN_COMMUNICATION
            audioManager.isSpeakerphoneOn = true
        } catch (e: Exception) {
            Log.e("BlueChat", "Error setting audio mode to communication", e)
        }

        val sampleRate = 16000
        val channelConfigIn = android.media.AudioFormat.CHANNEL_IN_MONO
        val channelConfigOut = android.media.AudioFormat.CHANNEL_OUT_MONO
        val audioFormat = android.media.AudioFormat.ENCODING_PCM_16BIT
        val minRecordBufSize = android.media.AudioRecord.getMinBufferSize(sampleRate, channelConfigIn, audioFormat)
        val minTrackBufSize = android.media.AudioTrack.getMinBufferSize(sampleRate, channelConfigOut, audioFormat)

        try {
            audioRecord = android.media.AudioRecord(
                android.media.MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                sampleRate,
                channelConfigIn,
                audioFormat,
                minRecordBufSize
            )

            val sessionId = audioRecord?.audioSessionId
            if (sessionId != null) {
                try {
                    if (android.media.audiofx.AcousticEchoCanceler.isAvailable()) {
                        echoCanceler = android.media.audiofx.AcousticEchoCanceler.create(sessionId)
                        echoCanceler?.enabled = true
                        Log.d("BlueChat", "AcousticEchoCanceler enabled")
                    }
                } catch (e: Exception) {}

                try {
                    if (android.media.audiofx.NoiseSuppressor.isAvailable()) {
                        noiseSuppressor = android.media.audiofx.NoiseSuppressor.create(sessionId)
                        noiseSuppressor?.enabled = true
                        Log.d("BlueChat", "NoiseSuppressor enabled")
                    }
                } catch (e: Exception) {}
            }

            audioTrack = android.media.AudioTrack(
                android.media.AudioManager.STREAM_VOICE_CALL,
                sampleRate,
                channelConfigOut,
                audioFormat,
                minTrackBufSize,
                android.media.AudioTrack.MODE_STREAM
            )
        } catch (e: SecurityException) {
            Log.e("BlueChat", "AudioRecord creation failed - permission missing", e)
            return
        } catch (e: Exception) {
            Log.e("BlueChat", "AudioRecord/AudioTrack creation failed", e)
            return
        }

        isCallActive = true
        isVideoCallActive = isVideo
        activeCallAddress = address

        if (isVideo) {
            startCamera()
        }

        try {
            audioRecord?.startRecording()
            audioTrack?.play()
        } catch (e: Exception) {
            Log.e("BlueChat", "Failed to start AudioRecord/AudioTrack", e)
            stopAudioCall()
            return
        }

        audioPlaybackQueue.clear()
        audioPlaybackThread = Thread {
            while (isCallActive) {
                try {
                    val audioChunk = audioPlaybackQueue.take()
                    audioTrack?.write(audioChunk, 0, audioChunk.size)
                } catch (e: InterruptedException) {
                    break
                } catch (e: Exception) {
                    Log.e("BlueChat", "Audio playback error", e)
                }
            }
        }.apply { start() }

        recordingThread = Thread {
            val buffer = ByteArray(minRecordBufSize)
            while (isCallActive) {
                val read = audioRecord?.read(buffer, 0, buffer.size) ?: -1
                if (read > 0) {
                    val audioChunk = buffer.copyOf(read)
                    val conn = activeConnections[address]
                    conn?.writeFrame(FRAME_TYPE_AUDIO, audioChunk)
                } else if (read < 0) {
                    break
                }
            }
        }.apply { start() }

        Log.d("BlueChat", "Voice call started successfully to $address (video: $isVideo)")
    }

    fun stopAudioCall() {
        if (!isCallActive) return
        stopAllAlerts()
        
        if (isVideoCallActive) {
            stopCamera()
        }
        
        isCallActive = false
        isVideoCallActive = false
        recordingThread = null

        audioPlaybackThread?.interrupt()
        audioPlaybackThread = null
        audioPlaybackQueue.clear()

        try {
            echoCanceler?.enabled = false
            echoCanceler?.release()
        } catch (e: Exception) {}
        echoCanceler = null

        try {
            noiseSuppressor?.enabled = false
            noiseSuppressor?.release()
        } catch (e: Exception) {}
        noiseSuppressor = null

        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
            audioManager.mode = oldAudioMode
            audioManager.isSpeakerphoneOn = oldIsSpeakerphoneOn
        } catch (e: Exception) {
            Log.e("BlueChat", "Error resetting audio mode", e)
        }

        try {
            audioRecord?.stop()
            audioRecord?.release()
        } catch (e: Exception) {}
        audioRecord = null

        try {
            audioTrack?.stop()
            audioTrack?.release()
        } catch (e: Exception) {}
        audioTrack = null
        activeCallAddress = null
        Log.d("BlueChat", "Voice call stopped")

        (context as? BluetoothForegroundService)?.updateForegroundTypes(hasMic = false, hasCamera = false)
    }

    companion object {
        private const val MSG_CHANNEL_ID = "BlueChat_Messages_Channel"
        private val APP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
        private const val NAME = "BlueChat"

        private const val FRAME_TYPE_TEXT = 1.toByte()
        private const val FRAME_TYPE_FILE_METADATA = 2.toByte()
        private const val FRAME_TYPE_FILE_CHUNK = 3.toByte()
        private const val FRAME_TYPE_ACK = 4.toByte()
        private const val FRAME_TYPE_AUDIO = 5.toByte()
        private const val FRAME_TYPE_VIDEO = 6.toByte()
    }
}
