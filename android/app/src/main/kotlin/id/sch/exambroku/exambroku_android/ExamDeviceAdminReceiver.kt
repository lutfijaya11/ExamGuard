package id.sch.exambroku.exambroku_android

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent

/**
 * Optional Device Admin / Device Owner receiver enabling full OS-level Lock Task Mode
 * when provisioned via ADB (`dpm set-device-owner`).
 */
class ExamDeviceAdminReceiver : DeviceAdminReceiver() {
    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
    }
}
