package android.view; public class View { public View(android.content.Context c){}
 public void setPadding(int l,int t,int r,int b){} public void setOnClickListener(OnClickListener l){} public void setBackgroundResource(int r){}
 public void setMinimumHeight(int h){} public void setAlpha(float a){} public void setClickable(boolean b){} public void setFocusable(boolean b){}
 public interface OnClickListener { void onClick(View v); } }