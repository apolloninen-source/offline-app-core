package offlineappcore.files;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;

// Opens the system file picker (Files, Drive, Downloads...) and reads the
// chosen file as UTF-8 text, for "Restore from a backup file". The result
// goes back to native code through onResult; nothing leaves the phone.
public class PickActivity extends Activity {
    private static final int PICK = 4711;
    private static final int MAX_BYTES = 8 * 1024 * 1024;

    // The file's bytes as they are (UTF-8): a Java String would reach native
    // code in "modified UTF-8", which garbles emoji in the player's notes.
    private static native void onResult(byte[] data, String error);

    // Called from native code.
    public static void open(Activity activity) {
        activity.startActivity(new Intent(activity, PickActivity.class));
    }

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        if (state != null) {
            return; // recreated while the picker is open: the result still arrives
        }
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*"); // saved backups may be labelled as text, JSON or unknown
        try {
            startActivityForResult(intent, PICK);
        } catch (Exception e) {
            onResult(null, "No file picker on this phone");
            finish();
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != PICK) {
            return;
        }
        if (resultCode != RESULT_OK || data == null || data.getData() == null) {
            onResult(null, "cancelled");
        } else {
            read(data.getData());
        }
        finish();
    }

    private void read(Uri uri) {
        try (InputStream in = getContentResolver().openInputStream(uri)) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buffer = new byte[16384];
            int n;
            while ((n = in.read(buffer)) > 0) {
                out.write(buffer, 0, n);
                if (out.size() > MAX_BYTES) {
                    onResult(null, "The file is too large to be a backup");
                    return;
                }
            }
            onResult(out.toByteArray(), null);
        } catch (Exception e) {
            onResult(null, "Could not read the file");
        }
    }
}
