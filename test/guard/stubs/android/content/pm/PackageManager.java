package android.content.pm;
public class PackageManager {
    public static java.util.Set<String> installed = new java.util.HashSet<>();
    public PackageInfo getPackageInfo(String pkg, int flags) throws NameNotFoundException {
        if (!installed.contains(pkg)) throw new NameNotFoundException(pkg);
        return new PackageInfo();
    }
    public static class NameNotFoundException extends Exception {
        public NameNotFoundException(String s) { super(s); }
    }
}
