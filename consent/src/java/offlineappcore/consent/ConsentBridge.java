package offlineappcore.consent;

import android.app.Activity;

import com.google.android.ump.ConsentDebugSettings;
import com.google.android.ump.ConsentForm;
import com.google.android.ump.ConsentInformation;
import com.google.android.ump.ConsentRequestParameters;
import com.google.android.ump.FormError;
import com.google.android.ump.UserMessagingPlatform;

// Google's consent form (UMP) for the Defold extension "consent". Every
// result goes back to native code through onResult, from any thread; the
// native side queues it for the Lua callback on the main thread.
public class ConsentBridge {
    public static final int REQUEST = 0;
    public static final int PRIVACY_OPTIONS = 1;

    private static native void onResult(int kind, boolean canRequestAds, String error);

    private static ConsentInformation info(Activity activity) {
        return UserMessagingPlatform.getConsentInformation(activity);
    }

    private static String message(FormError error) {
        return error == null ? null : error.getErrorCode() + ": " + error.getMessage();
    }

    // Updates the consent status and shows the form if the player still has
    // to answer it (only where the law asks for it).
    public static void request(final Activity activity, final boolean debugEea, final String testDeviceId) {
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                ConsentRequestParameters.Builder params = new ConsentRequestParameters.Builder();
                boolean hasDevice = testDeviceId != null && !testDeviceId.isEmpty();
                if (debugEea || hasDevice) {
                    ConsentDebugSettings.Builder debug = new ConsentDebugSettings.Builder(activity);
                    if (debugEea) {
                        debug.setDebugGeography(ConsentDebugSettings.DebugGeography.DEBUG_GEOGRAPHY_EEA);
                    }
                    if (hasDevice) {
                        debug.addTestDeviceHashedId(testDeviceId);
                    }
                    params.setConsentDebugSettings(debug.build());
                }
                final ConsentInformation consent = info(activity);
                consent.requestConsentInfoUpdate(activity, params.build(),
                    new ConsentInformation.OnConsentInfoUpdateSuccessListener() {
                        @Override
                        public void onConsentInfoUpdateSuccess() {
                            UserMessagingPlatform.loadAndShowConsentFormIfRequired(activity,
                                new ConsentForm.OnConsentFormDismissedListener() {
                                    @Override
                                    public void onConsentFormDismissed(FormError error) {
                                        onResult(REQUEST, consent.canRequestAds(), message(error));
                                    }
                                });
                        }
                    },
                    new ConsentInformation.OnConsentInfoUpdateFailureListener() {
                        @Override
                        public void onConsentInfoUpdateFailure(FormError error) {
                            onResult(REQUEST, consent.canRequestAds(), message(error));
                        }
                    });
            }
        });
    }

    public static boolean canRequestAds(Activity activity) {
        return info(activity).canRequestAds();
    }

    // True where the player must be able to change their choice later: the
    // app then shows a "Privacy choices" link.
    public static boolean privacyOptionsRequired(Activity activity) {
        return info(activity).getPrivacyOptionsRequirementStatus()
            == ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED;
    }

    public static void showPrivacyOptions(final Activity activity) {
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                UserMessagingPlatform.showPrivacyOptionsForm(activity,
                    new ConsentForm.OnConsentFormDismissedListener() {
                        @Override
                        public void onConsentFormDismissed(FormError error) {
                            onResult(PRIVACY_OPTIONS, info(activity).canRequestAds(), message(error));
                        }
                    });
            }
        });
    }

    // For testing only: forget the answer, so the form shows again.
    public static void reset(Activity activity) {
        info(activity).reset();
    }
}
