package com.wewaffles.anygsi;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;

public class RootReceiver extends BroadcastReceiver {
    private static final String TAG = "RootReceiver";
    private static final String[][] CANDIDATES = {
        {"/data/adb/ksud", "debug", "su"},
        {"/data/adb/ksu/bin/su"},
        {"/data/user_de/0/df.root/ksud", "debug", "su"},
        {"/data/user_de/0/df.root/ksud"},
        {"/system/bin/su"},
        {"/system/xbin/su"},
        {"su"}
    };

    private static String[] getSuPrefix() {
        try {
            File dfKsud = new File("/data/user_de/0/df.root/ksud");
            if (dfKsud.exists() && dfKsud.canExecute()) {
                Runtime.getRuntime().exec(new String[]{dfKsud.getAbsolutePath(), "install"}).waitFor();
            }
        } catch (Exception e) {
            Log.w(TAG, "ksud install failed: " + e.getMessage());
        }

        for (String[] c : CANDIDATES) {
            try {
                String[] testCmd = new String[c.length + 2];
                System.arraycopy(c, 0, testCmd, 0, c.length);
                testCmd[c.length] = "-c";
                testCmd[c.length + 1] = "id";

                Process p = Runtime.getRuntime().exec(testCmd);
                BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()));
                String line = r.readLine();
                if (p.waitFor() == 0 && line != null && line.contains("uid=0")) {
                    Log.i(TAG, "Found working su candidate: " + c[0]);
                    return c;
                }
            } catch (Exception e) {
                // ignore
            }
        }
        return new String[]{"su"};
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        String cmd = intent.getStringExtra("cmd");
        if (cmd == null || cmd.isEmpty()) {
            File runSh = new File("/data/local/tmp/run_root.sh");
            if (runSh.exists()) {
                cmd = "/system/bin/sh /data/local/tmp/run_root.sh";
            } else {
                cmd = "id";
            }
        }
        final String finalCmd = cmd;
        Log.i(TAG, "Received command to execute: " + finalCmd);
        new Thread(() -> {
            try {
                String[] suPrefix = getSuPrefix();
                String[] runCmd = new String[suPrefix.length + 2];
                System.arraycopy(suPrefix, 0, runCmd, 0, suPrefix.length);
                runCmd[suPrefix.length] = "-c";
                runCmd[suPrefix.length + 1] = finalCmd;

                Log.i(TAG, "Executing via " + suPrefix[0] + ": " + finalCmd);
                Process p = new ProcessBuilder(runCmd).start();
                
                File outFile = new File("/data/local/tmp/cmd_out.txt");
                try (InputStream in = p.getInputStream();
                     InputStream err = p.getErrorStream();
                     FileOutputStream fos = new FileOutputStream(outFile)) {
                    byte[] buf = new byte[4096];
                    int len;
                    while ((len = in.read(buf)) != -1) {
                        fos.write(buf, 0, len);
                    }
                    while ((len = err.read(buf)) != -1) {
                        fos.write(buf, 0, len);
                    }
                }
                p.waitFor();
                outFile.setReadable(true, false);
                outFile.setWritable(true, false);
                Log.i(TAG, "Command finished with exit code: " + p.exitValue());
            } catch (Exception e) {
                Log.e(TAG, "Execution error: ", e);
            }
        }).start();
    }
}
