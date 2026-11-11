package android.content.pm;
public class PackageManager {
    public static java.util.Set<String> installed = new java.util.HashSet<>();
    public PackageInfo getPackageInfo(String pkg, int flags) throws NameNotFoundException {
        if (!installed.contains(pkg)) throw new NameNotFoundException(pkg);
        return new PackageInfo();
    }
    public android.content.Intent getLaunchIntentForPackage(String pkg) {
        return installed.contains(pkg) ? new android.content.Intent("launch:" + pkg) : null;
    }
    public static class NameNotFoundException extends Exception {
        public NameNotFoundException(String s) { super(s); }
    }
}
