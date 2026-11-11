package com.noxis.guard;
import android.content.*;
import java.util.*;
public class FakeCtx extends GuardApp {
  final Map<String,Object> m = new HashMap<>();
  final SharedPreferences sp = new SharedPreferences() {
    public int getInt(String k,int d){return m.containsKey(k)?(Integer)m.get(k):d;}
    public boolean getBoolean(String k,boolean d){return m.containsKey(k)?(Boolean)m.get(k):d;}
    public String getString(String k,String d){return m.containsKey(k)?(String)m.get(k):d;}
    public Editor edit(){ return new Editor(){
      public Editor putInt(String k,int v){m.put(k,v);return this;}
      public Editor putBoolean(String k,boolean v){m.put(k,v);return this;}
      public Editor putString(String k,String v){m.put(k,v);return this;}
      public void apply(){} }; }
  };
  @Override public SharedPreferences getSharedPreferences(String n,int mode){return sp;}
  @Override public java.util.concurrent.Executor getMainExecutor(){return Runnable::run;}
  @SuppressWarnings("unchecked") @Override public <T> T getSystemService(Class<T> c){
    try { if (c==android.bluetooth.BluetoothManager.class) return null; return c.getDeclaredConstructor().newInstance(); } catch(Exception e){ throw new RuntimeException(e);} }
}
