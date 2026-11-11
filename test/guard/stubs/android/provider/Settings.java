package android.provider; import android.content.ContentResolver; public final class Settings {
 public static final java.util.Map<String,String> store = new java.util.HashMap<>();
 public static final String ACTION_MANAGE_DEFAULT_APPS_SETTINGS = "android.settings.MANAGE_DEFAULT_APPS_SETTINGS";
 public static final String ACTION_APPLICATION_SETTINGS = "android.settings.APPLICATION_SETTINGS";
 public static final class Global {
  public static boolean putInt(ContentResolver c,String k,int v){android.Rec.r("g:"+k+"="+v);store.put("g:"+k,""+v);return true;}
  public static boolean putString(ContentResolver c,String k,String v){android.Rec.r("g:"+k+"="+v);store.put("g:"+k,v);return true;}
  public static int getInt(ContentResolver c,String k,int d){String v=store.get("g:"+k);return v==null?d:Integer.parseInt(v);}
  public static String getString(ContentResolver c,String k){return store.get("g:"+k);} }
 public static final class Secure {
  public static boolean putInt(ContentResolver c,String k,int v){android.Rec.r("s:"+k+"="+v);store.put("s:"+k,""+v);return true;}
  public static int getInt(ContentResolver c,String k,int d){String v=store.get("s:"+k);return v==null?d:Integer.parseInt(v);}
  public static String getString(ContentResolver c,String k){return store.get("s:"+k);} } }
