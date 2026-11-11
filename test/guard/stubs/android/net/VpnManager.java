package android.net;
public class VpnManager {
    public boolean setAlwaysOnVpnPackageForUser(int userId, String pkg, boolean lockdown, java.util.List<String> allow) {
        android.Rec.r("vpn:" + pkg + ":" + lockdown);
        return true;
    }
}
