package android.app; public class KeyguardManager { public static boolean locked=true; public static KeyguardLockedStateListener l;
 public boolean isDeviceLocked(){return locked;}
 public void addKeyguardLockedStateListener(java.util.concurrent.Executor e, KeyguardLockedStateListener l){KeyguardManager.l=l;}
 @FunctionalInterface public interface KeyguardLockedStateListener { void onKeyguardLockedStateChanged(boolean locked); } }