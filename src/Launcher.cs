// Оболочка PCCleaner.exe: запускает встроенный в exe скрипт PCCleaner.ps1
// внутри собственного процесса (без окна консоли и без powershell.exe).
using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows.Forms;

static class Program
{
    [STAThread]
    static void Main()
    {
        try
        {
            // Разрешить загрузку системных модулей (Appx, ScheduledTasks) только для этого процесса
            Environment.SetEnvironmentVariable("PSExecutionPolicyPreference", "Bypass");

            Assembly asm = Assembly.GetExecutingAssembly();
            string script;
            using (Stream s = asm.GetManifestResourceStream("PCCleaner.ps1"))
            using (StreamReader r = new StreamReader(s, Encoding.UTF8))
            {
                script = r.ReadToEnd();
            }

            using (Runspace rs = RunspaceFactory.CreateRunspace())
            {
                rs.ApartmentState = ApartmentState.STA;
                rs.ThreadOptions = PSThreadOptions.UseCurrentThread;
                rs.Open();
                rs.SessionStateProxy.SetVariable("PCCAppDir", Path.GetDirectoryName(asm.Location));
                using (PowerShell ps = PowerShell.Create())
                {
                    ps.Runspace = rs;
                    ps.AddScript(script);
                    ps.Invoke();
                }
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "PCCleaner", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
