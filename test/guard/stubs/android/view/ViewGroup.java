package android.view; public abstract class ViewGroup extends View { public ViewGroup(android.content.Context c){super(c);}
 public void addView(View v){} public void addView(View v, LayoutParams p){} public void removeAllViews(){}
 public static class LayoutParams { public static final int WRAP_CONTENT=-2; public static final int MATCH_PARENT=-1; public LayoutParams(int w,int h){} } }