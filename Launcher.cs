using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
class FountainLauncher {
 [STAThread] static void Main() {
  string root=AppDomain.CurrentDomain.BaseDirectory;
  try {
   var start=new ProcessStartInfo(Path.Combine(Environment.SystemDirectory,@"WindowsPowerShell\v1.0\powershell.exe"));
   start.Arguments="-NoProfile -ExecutionPolicy Bypass -STA -File \""+Path.Combine(root,"DotaSettings.ps1")+"\"";
   start.WorkingDirectory=root; start.UseShellExecute=false; start.CreateNoWindow=true;
   start.RedirectStandardError=true;
   using(var p=Process.Start(start)) {
    string error=p.StandardError.ReadToEnd();p.WaitForExit();
    if(p.ExitCode!=0) {Directory.CreateDirectory(Path.Combine(root,"data"));File.WriteAllText(Path.Combine(root,"data","startup-error.log"),error);MessageBox.Show("启动未完成。请查看程序目录 data/startup-error.log。\n"+error,"泉印");}
   }
  }catch(Exception ex){MessageBox.Show(ex.Message,"泉印");}
 }
}
