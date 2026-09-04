package com.kiya.bankinggenie

import android.content.Intent
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MetaversePlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "MetaversePlugin"
        private const val CHANNEL = "com.kiya.bankinggenie/metaverse"
    }

    private lateinit var channel: MethodChannel
    private var activityBinding: ActivityPluginBinding? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activityBinding = binding }
    override fun onDetachedFromActivity() { activityBinding = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activityBinding = binding }
    override fun onDetachedFromActivityForConfigChanges() { activityBinding = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "launch") {
            try {
                val activity = activityBinding?.activity ?: run {
                    result.error("NO_ACTIVITY", "Activity not available", null); return
                }
                val intent = Intent().apply {
                    setClassName(activity, "com.kiya.bankinggenie.MetaverseActivity")
                    addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                }
                activity.startActivity(intent)
                result.success("launched")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to launch Metaverse: ${e.message}")
                result.error("LAUNCH_FAILED", e.message, null)
            }
        } else {
            result.notImplemented()
        }
    }
}
