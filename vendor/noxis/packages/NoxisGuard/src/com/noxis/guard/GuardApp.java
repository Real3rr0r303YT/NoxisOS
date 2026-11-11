package com.noxis.guard;

import android.app.Application;

/** Persistente System-App: startet beim Booten (auch vor dem ersten Entsperren). */
public class GuardApp extends Application {
    @Override
    public void onCreate() {
        super.onCreate();
        Hardening.applyOnce(this);
        GuardController.get(this).start();
    }
}
