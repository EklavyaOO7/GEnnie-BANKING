package com.kiya.bankinggenie

import android.content.Intent
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Process
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat

class MainActivity : FlutterFragmentActivity() {
    private var intentChannel: MethodChannel? = null
    private var pendingDeepLink: String? = null
    private var flutterReady = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureDeepLink(intent)
        Log.d("DeepLink", "onCreate pendingDeepLink=$pendingDeepLink")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(SlmPlugin())
        flutterEngine.plugins.add(MetaversePlugin())
        intentChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.kiya.bankinggenie/intent")
        intentChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialIntent" -> {
                    Log.d("DeepLink", "getInitialIntent called → $pendingDeepLink")
                    result.success(pendingDeepLink)
                    pendingDeepLink = null
                }
                "flutterReady" -> {
                    flutterReady = true
                    val link = pendingDeepLink
                    pendingDeepLink = null
                    if (link != null) {
                        Log.d("DeepLink", "flutterReady — returning $link")
                        result.success(link)  // return the deep link directly as the response
                    } else {
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.kiya.bankinggenie/app")
            .setMethodCallHandler { call, _ ->
                if (call.method == "exitApp") {
                    finishAffinity()
                    Process.killProcess(Process.myPid())
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.kiya.bankinggenie/biometric")
            .setMethodCallHandler { call, result ->
                if (call.method != "authenticate") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                runOnUiThread {
                    val manager = BiometricManager.from(this)
                    val canAuth = manager.canAuthenticate(
                        BiometricManager.Authenticators.BIOMETRIC_STRONG or
                        BiometricManager.Authenticators.DEVICE_CREDENTIAL
                    )
                    if (canAuth != BiometricManager.BIOMETRIC_SUCCESS) {
                        result.success("success")
                        return@runOnUiThread
                    }
                    val executor = ContextCompat.getMainExecutor(this)
                    val callback = object : BiometricPrompt.AuthenticationCallback() {
                        override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult) {
                            result.success("success")
                        }
                        override fun onAuthenticationError(code: Int, msg: CharSequence) {
                            if (code == BiometricPrompt.ERROR_USER_CANCELED ||
                                code == BiometricPrompt.ERROR_NEGATIVE_BUTTON) {
                                result.success("cancelled")
                            } else {
                                result.success("success")
                            }
                        }
                        override fun onAuthenticationFailed() {}
                    }
                    val prompt = BiometricPrompt(this, executor, callback)
                    val info = BiometricPrompt.PromptInfo.Builder()
                        .setTitle("Authenticate Transfer")
                        .setSubtitle("Confirm your identity to proceed")
                        .setAllowedAuthenticators(
                            BiometricManager.Authenticators.BIOMETRIC_STRONG or
                            BiometricManager.Authenticators.DEVICE_CREDENTIAL
                        )
                        .build()
                    prompt.authenticate(info)
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        captureDeepLink(intent)
        Log.d("DeepLink", "onNewIntent pendingDeepLink=$pendingDeepLink")
        intentChannel?.invokeMethod("onIntent", pendingDeepLink)
        pendingDeepLink = null
    }

    private fun captureDeepLink(intent: Intent?) {
        val uri = intent?.data ?: return
        if (uri.scheme != "bankinggenie") return
        val branchID = uri.getQueryParameter("branchID") ?: ""
        val token = uri.getQueryParameter("token") ?: ""
        pendingDeepLink = """{"host":"${uri.host}","branchID":"$branchID","token":"$token"}"""
        Log.d("DeepLink", "captured: $pendingDeepLink")
    }
}
