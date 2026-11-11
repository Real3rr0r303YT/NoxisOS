package android.net; public class ConnectivityManager { public static NetworkCallback cb;
 public void registerNetworkCallback(NetworkRequest r, NetworkCallback cb){ConnectivityManager.cb=cb;}
 public static class NetworkCallback { public void onAvailable(Network n){} public void onLost(Network n){} } }