package android.content;
import android.content.res.Resources;
public abstract class Context {
  public static final int MODE_PRIVATE=0; public static final int RECEIVER_NOT_EXPORTED=4;
  public Context createDeviceProtectedStorageContext(){return this;}
  public SharedPreferences getSharedPreferences(String n,int m){return null;}
  public ContentResolver getContentResolver(){return null;}
  public <T> T getSystemService(Class<T> c){return null;}
  public Context getApplicationContext(){return this;}
  public java.util.concurrent.Executor getMainExecutor(){return null;}
  public Intent registerReceiver(BroadcastReceiver r, IntentFilter f, int flags){return null;}
  public String getPackageName(){return "";}
  public android.content.pm.PackageManager getPackageManager(){return new android.content.pm.PackageManager();}
  public Resources getResources(){return null;}
  public Resources.Theme getTheme(){return null;}
}