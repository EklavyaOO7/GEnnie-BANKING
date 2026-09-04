package com.kiya.bankinggenie

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.KeyEvent
import android.window.OnBackInvokedDispatcher
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.unity3d.player.UnityPlayerGameActivity

class MetaverseActivity : UnityPlayerGameActivity() {

    companion object {
        private const val TAG = "MetaverseActivity"
        private const val REQ_AUDIO = 1001
    }

    private var mCallbackRegistered = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
                != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this,
                arrayOf(Manifest.permission.RECORD_AUDIO), REQ_AUDIO)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_AUDIO) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            Log.d(TAG, "RECORD_AUDIO permission ${if (granted) "granted" else "denied"}")
        }
    }

    override fun onResume() {
        super.onResume()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !mCallbackRegistered) {
            onBackInvokedDispatcher.registerOnBackInvokedCallback(
                OnBackInvokedDispatcher.PRIORITY_DEFAULT
            ) {
                Log.d(TAG, "Back invoked - finishing")
                finish()
            }
            mCallbackRegistered = true
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.keyCode == KeyEvent.KEYCODE_BACK && event.action == KeyEvent.ACTION_UP) {
            Log.d(TAG, "dispatchKeyEvent BACK - finishing")
            finish()
            return true
        }
        return super.dispatchKeyEvent(event)
    }
}
