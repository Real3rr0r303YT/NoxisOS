package android.app; import android.content.*; public class AlertDialog implements DialogInterface { public void dismiss(){}
 public static class Builder { public Builder(Context c){}
  public Builder setTitle(CharSequence t){return this;}
  public Builder setSingleChoiceItems(CharSequence[] items,int checked, DialogInterface.OnClickListener l){return this;}
  public Builder setNegativeButton(int res, DialogInterface.OnClickListener l){return this;}
  public AlertDialog show(){return null;} } }