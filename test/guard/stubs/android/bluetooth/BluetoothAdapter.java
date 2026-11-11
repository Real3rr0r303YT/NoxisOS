package android.bluetooth; public final class BluetoothAdapter {
 public static final String ACTION_STATE_CHANGED="a"; public static final String ACTION_CONNECTION_STATE_CHANGED="b";
 public boolean isEnabled(){return false;} public int getProfileConnectionState(int p){return 0;} @Deprecated public boolean disable(){return true;} }