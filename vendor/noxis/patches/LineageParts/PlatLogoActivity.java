/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Noxis OS – Copyright (C) 2026 3rr0r (Real3rr0r303YT) – Made by 3rr0r303YT on TikTok
 *
 * Noxis easter egg (replaces the LineageOS one – Settings → About phone → tap
 * "NoxisOS version" several times). A Nothing-style dot matrix draws the Noxis
 * mark (open ring + N). Every touch sends a wave through the dots; after seven
 * taps a message appears; a long press shows who made it.
 */
package org.lineageos.lineageparts.logo;

import android.app.Activity;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.MotionEvent;
import android.view.View;
import android.widget.Toast;

import java.util.ArrayList;

public class PlatLogoActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(new EggView(this));
    }

    private static final class EggView extends View {
        private static final int WHITE = 0xFFF0F4FA;
        private static final int BLUE = 0xFF7FA8FF;
        private static final int DIM = 0x33FFFFFF;
        private static final int TAPS_FOR_MESSAGE = 7;

        private final Paint mDot = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint mText = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final ArrayList<float[]> mRipples = new ArrayList<>(); // x, y, start (ms since mStart)
        private final long mStart = SystemClock.uptimeMillis();
        private float[] mX = new float[0];
        private float[] mY = new float[0];
        private byte[] mType = new byte[0];   // 0 = background, 1 = mark (white), 2 = N diagonal (blue)
        private float[] mDelay = new float[0]; // intro: mark dots appear from the centre
        private float mStep;
        private float mMarkRadius;
        private int mTaps;
        private long mRevealAt = -1;
        private long mDownAt;

        EggView(Context context) {
            super(context);
            setBackgroundColor(Color.BLACK);
            mText.setColor(WHITE);
            mText.setTextAlign(Paint.Align.CENTER);
            mText.setTypeface(Typeface.create(Typeface.MONOSPACE, Typeface.BOLD));
            setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN);
        }

        @Override
        protected void onSizeChanged(int w, int h, int oldw, int oldh) {
            mStep = Math.max(12f, Math.min(w, h) / 30f);
            mMarkRadius = Math.min(w, h) * 0.30f;
            float cx = w / 2f, cy = h / 2f;
            int cols = (int) (w / mStep) + 1, rows = (int) (h / mStep) + 1;
            float offX = (w - (cols - 1) * mStep) / 2f, offY = (h - (rows - 1) * mStep) / 2f;
            int n = cols * rows;
            mX = new float[n]; mY = new float[n]; mType = new byte[n]; mDelay = new float[n];
            float thick = mStep * 0.62f;
            float r = mMarkRadius;
            float nx = 0.33f * r, ny = 0.42f * r;
            int i = 0;
            for (int row = 0; row < rows; row++) {
                for (int col = 0; col < cols; col++, i++) {
                    float x = offX + col * mStep, y = offY + row * mStep;
                    mX[i] = x; mY[i] = y;
                    float dx = x - cx, dy = y - cy;
                    float dist = (float) Math.hypot(dx, dy);
                    double ang = Math.toDegrees(Math.atan2(dy, dx)); // screen coords: -90 = top
                    boolean inGap = ang > -81 && ang < -48;
                    byte t = 0;
                    if (Math.abs(dist - r) < thick && !inGap) t = 1;
                    if (segDist(dx, dy, -nx, -ny, -nx, ny) < thick || segDist(dx, dy, nx, -ny, nx, ny) < thick) t = 1;
                    if (segDist(dx, dy, -nx, -ny, nx, ny) < thick) t = 2;
                    mType[i] = t;
                    mDelay[i] = dist / (r * 1.4f); // 0..~1 s
                }
            }
        }

        private static float segDist(float px, float py, float ax, float ay, float bx, float by) {
            float vx = bx - ax, vy = by - ay;
            float len2 = vx * vx + vy * vy;
            float t = len2 == 0 ? 0 : Math.max(0, Math.min(1, ((px - ax) * vx + (py - ay) * vy) / len2));
            float qx = ax + t * vx - px, qy = ay + t * vy - py;
            return (float) Math.sqrt(qx * qx + qy * qy);
        }

        @Override
        protected void onDraw(Canvas canvas) {
            long now = SystemClock.uptimeMillis();
            float since = (now - mStart) / 1000f;
            boolean animating = since < 1.6f;
            float speed = Math.max(getWidth(), getHeight()) * 0.9f; // px per second
            for (int r = mRipples.size() - 1; r >= 0; r--) {
                if ((now - mStart - mRipples.get(r)[2]) / 1000f > 1.4f) mRipples.remove(r);
            }
            if (!mRipples.isEmpty()) animating = true;
            float base = mStep * 0.16f, lit = mStep * 0.30f;
            for (int i = 0; i < mX.length; i++) {
                float wave = 0f;
                for (float[] rp : mRipples) {
                    float age = (now - mStart - rp[2]) / 1000f;
                    float d = Math.abs((float) Math.hypot(mX[i] - rp[0], mY[i] - rp[1]) - age * speed);
                    if (d < mStep * 1.6f) wave = Math.max(wave, (1 - d / (mStep * 1.6f)) * (1 - age / 1.4f));
                }
                int color;
                float radius;
                if (mType[i] != 0) {
                    float k = Math.max(0, Math.min(1, (since - mDelay[i] * 0.8f) / 0.35f));
                    color = blend(DIM, mType[i] == 2 ? BLUE : WHITE, k);
                    radius = base + (lit - base) * k;
                    if (wave > 0) color = blend(color, BLUE, wave * 0.6f);
                } else {
                    color = blend(DIM, BLUE, wave);
                    radius = base + (lit - base) * wave;
                }
                mDot.setColor(color);
                canvas.drawCircle(mX[i], mY[i], radius, mDot);
            }
            if (mRevealAt > 0) {
                float k = Math.min(1, (now - mRevealAt) / 600f);
                if (k < 1) animating = true;
                mText.setAlpha((int) (255 * k));
                float y = getHeight() / 2f + mMarkRadius * 1.5f;
                mText.setTextSize(mStep * 1.2f);
                mText.setColor(WHITE);
                mText.setAlpha((int) (255 * k));
                canvas.drawText("STAY PRIVATE.", getWidth() / 2f, y, mText);
                mText.setTextSize(mStep * 0.6f);
                mText.setColor(BLUE);
                mText.setAlpha((int) (255 * k));
                canvas.drawText("NOXIS OS", getWidth() / 2f, y + mStep * 1.3f, mText);
            }
            if (animating) postInvalidateOnAnimation();
        }

        private static int blend(int a, int b, float k) {
            k = Math.max(0, Math.min(1, k));
            int aa = (a >>> 24), ar = (a >> 16) & 0xFF, ag = (a >> 8) & 0xFF, ab = a & 0xFF;
            int ba = (b >>> 24), br = (b >> 16) & 0xFF, bg = (b >> 8) & 0xFF, bb = b & 0xFF;
            return ((int) (aa + (ba - aa) * k) << 24) | ((int) (ar + (br - ar) * k) << 16)
                    | ((int) (ag + (bg - ag) * k) << 8) | (int) (ab + (bb - ab) * k);
        }

        @Override
        public boolean onTouchEvent(MotionEvent e) {
            switch (e.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    mDownAt = SystemClock.uptimeMillis();
                    mRipples.add(new float[] {e.getX(), e.getY(), mDownAt - mStart});
                    if (++mTaps == TAPS_FOR_MESSAGE) mRevealAt = mDownAt;
                    postInvalidateOnAnimation();
                    return true;
                case MotionEvent.ACTION_UP:
                    if (SystemClock.uptimeMillis() - mDownAt > 800) {
                        Toast.makeText(getContext(), "Made by 3rr0r303YT on TikTok", Toast.LENGTH_LONG).show();
                    } else {
                        performClick();
                    }
                    return true;
                default:
                    return true;
            }
        }

        @Override
        public boolean performClick() {
            return super.performClick();
        }
    }
}
