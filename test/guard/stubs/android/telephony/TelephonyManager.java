package android.telephony;
public class TelephonyManager {
    public static final long NETWORK_TYPE_BITMASK_GSM = 1L << 15;
    public static final long NETWORK_TYPE_BITMASK_GPRS = 1L << 0;
    public static final long NETWORK_TYPE_BITMASK_EDGE = 1L << 1;
    public static final long NETWORK_TYPE_BITMASK_CDMA = 1L << 3;
    public static final long NETWORK_TYPE_BITMASK_1xRTT = 1L << 6;
    public static final long NETWORK_TYPE_BITMASK_LTE = 1L << 12;
    public static final long NETWORK_TYPE_BITMASK_NR = 1L << 19;
    public static final int ALLOWED_NETWORK_TYPES_REASON_ENABLE_2G = 3;
    public static long allowed = 0xFFFFFL;   // alles erlaubt (Werkszustand)
    public long getAllowedNetworkTypesForReason(int reason) { return allowed; }
    public void setAllowedNetworkTypesForReason(int reason, long types) {
        allowed = types;
        android.Rec.r("2g:" + ((types & (NETWORK_TYPE_BITMASK_GSM | NETWORK_TYPE_BITMASK_EDGE)) != 0));
    }
}
