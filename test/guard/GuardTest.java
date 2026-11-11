package com.noxis.guard;
import android.Rec;
import android.app.KeyguardManager;
import java.util.List;
public class GuardTest {
  static int fails=0;
  static void check(String n, boolean ok){ System.out.println((ok?"PASS ":"FAIL ")+n+(ok?"":"  "+Rec.log)); if(!ok)fails++; }
  static boolean has(String p){ for(String s:Rec.log) if(s.startsWith(p)) return true; return false; }
  public static void main(String[] a){
    FakeCtx ctx=new FakeCtx();
    KeyguardManager.locked=true;
    GuardApp app=ctx;
    app.onCreate();
    check("Härtung: MAC-Randomisierung", Rec.log.contains("g:wifi_non_persistent_mac_randomization_force_enabled=1"));
    check("Härtung: Private DNS Quad9", Rec.log.contains("g:private_dns_specifier=dns.quad9.net") && Rec.log.contains("g:private_dns_mode=hostname"));
    check("Härtung: Konnektivitätscheck aus", Rec.log.contains("g:captive_portal_mode=0"));
    check("Härtung: Benachrichtigungen verborgen", Rec.log.contains("s:lock_screen_allow_private_notifications=0"));
    check("Härtung: 2G gesperrt (GSM/EDGE/CDMA)", Rec.log.contains("2g:false")
        && (android.telephony.TelephonyManager.allowed & Hardening.BITMASK_2G) == 0
        && (android.telephony.TelephonyManager.allowed & android.telephony.TelephonyManager.NETWORK_TYPE_BITMASK_LTE) != 0
        && (android.telephony.TelephonyManager.allowed & android.telephony.TelephonyManager.NETWORK_TYPE_BITMASK_NR) != 0);
    java.util.List<Status.Item> st = Status.check(ctx);
    check("Status: 7/8 nach Härtung, nur Killswitch fehlt (Mullvad noch nicht verbunden)",
        Status.score(st) == 7 && st.size() == 8 && !st.get(0).ok && st.get(0).title.startsWith("Mullvad"));
    android.provider.Settings.store.put("s:always_on_vpn_app", Prefs.MULLVAD);
    android.provider.Settings.store.put("s:always_on_vpn_lockdown", "1");
    check("Status: 8/8 mit Mullvad Always-on + Lockdown", Status.score(Status.check(ctx)) == 8);
    android.provider.Settings.store.put("s:always_on_vpn_lockdown", "0");
    check("Status: VPN ohne Lockdown zählt nicht als Killswitch", !Status.check(ctx).get(0).ok);
    check("BFU: USB-Daten aus", Rec.log.contains("usb:false"));
    check("BFU: Neustart-Timer 18h", has("alarm:com.noxis.guard.REBOOT_CHECK:"+18*3600000L));
    Rec.log.clear(); app.onCreate();
    check("Härtung nur einmal", !has("g:"));
    Rec.log.clear(); KeyguardManager.locked=false; KeyguardManager.l.onKeyguardLockedStateChanged(false);
    check("Entsperrt: USB an + Timer weg", Rec.log.contains("usb:true") && Rec.log.contains("cancel:com.noxis.guard.REBOOT_CHECK"));
    Rec.log.clear(); GuardController.get(app).onAlarm(GuardController.ACTION_REBOOT);
    check("Alarm entsperrt: kein Neustart", !has("reboot"));
    KeyguardManager.locked=true; KeyguardManager.l.onKeyguardLockedStateChanged(true);
    Rec.log.clear(); GuardController.get(app).onAlarm(GuardController.ACTION_REBOOT);
    check("Alarm gesperrt: Neustart", Rec.log.contains("reboot:noxis-auto-reboot"));
    ctx.sp.edit().putBoolean(Prefs.USB_LOCK,false).apply(); ctx.sp.edit().putInt(Prefs.AUTO_REBOOT_HOURS,0).apply();
    Rec.log.clear(); KeyguardManager.l.onKeyguardLockedStateChanged(true);
    check("USB-Sperre aus respektiert", !Rec.log.contains("usb:false"));
    check("Auto-Neustart aus respektiert", !has("alarm:com.noxis.guard.REBOOT_CHECK") && Rec.log.contains("cancel:com.noxis.guard.REBOOT_CHECK"));
    // WLAN Auto-Aus
    ctx.sp.edit().putInt(Prefs.WIFI_OFF_MIN,10).apply();
    Rec.log.clear(); GuardController.get(app).applySettings();
    check("WLAN an+getrennt: 10-min-Timer", has("alarm:com.noxis.guard.WIFI_CHECK:600000"));
    android.net.Network w1 = new android.net.Network();
    android.net.ConnectivityManager.cb.onAvailable(w1);
    Rec.log.clear(); GuardController.get(app).onAlarm(GuardController.ACTION_WIFI);
    check("WLAN verbunden: bleibt an", !Rec.log.contains("wifi:false"));
    Rec.log.clear(); android.net.ConnectivityManager.cb.onLost(w1);
    check("WLAN getrennt: Timer neu", has("alarm:com.noxis.guard.WIFI_CHECK:600000"));
    Rec.log.clear(); GuardController.get(app).onAlarm(GuardController.ACTION_WIFI);
    check("WLAN getrennt + Ablauf: WLAN aus", Rec.log.contains("wifi:false"));
    // Mullvad Killswitch
    check("Ohne Mullvad: kein VPN gesetzt", !has("vpn:"));
    android.content.pm.PackageManager.installed.add(Prefs.MULLVAD);
    Rec.log.clear(); KeyguardManager.locked=false; KeyguardManager.l.onKeyguardLockedStateChanged(false);
    check("Erstes Entsperren mit Mullvad: Always-on + Killswitch", Rec.log.contains("vpn:net.mullvad.mullvadvpn:true"));
    Rec.log.clear(); KeyguardManager.l.onKeyguardLockedStateChanged(false);
    check("Killswitch nur einmal automatisch", !has("vpn:"));
    Rec.log.clear(); Hardening.applyVpn(app, false);
    check("Killswitch abschaltbar", Rec.log.contains("vpn:null:false"));
    Rec.log.clear(); Hardening.apply2g(app, false);
    check("2G: schon gesperrt → kein erneuter Aufruf", !Rec.log.contains("2g:false"));
    Rec.log.clear(); Hardening.apply2g(app, true);
    check("2G wieder erlaubbar (Schalter)", Rec.log.contains("2g:true")
        && (android.telephony.TelephonyManager.allowed & Hardening.BITMASK_2G) == Hardening.BITMASK_2G);
    System.exit(fails==0?0:1);
  }
}
