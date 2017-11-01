/*
 * Copyright 2017 Martijn Brekhof. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.xbmc.kore.testhelpers;


import android.Manifest;
import android.app.Activity;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.os.Environment;
import android.support.v4.app.ActivityCompat;
import android.view.View;

import org.junit.rules.TestRule;
import org.junit.runner.Description;
import org.junit.runners.model.Statement;
import org.xbmc.kore.utils.LogUtils;

import java.io.File;
import java.io.FileOutputStream;
import java.text.SimpleDateFormat;
import java.util.Date;

import static org.xbmc.kore.testhelpers.EspressoTestUtils.getActivity;

public class TakeScreenshotRule implements TestRule {
    private final static String TAG = LogUtils.makeLogTag(TakeScreenshotRule.class);

    private class TakeScreenshotStatement extends Statement {
        private final Statement statement;
        private final Description description;

        TakeScreenshotStatement(Statement statement, Description description) {
            this.statement = statement;
            this.description = description;
        }

        @Override
        public void evaluate() throws Throwable {
            try {
                statement.evaluate();
            } catch (Throwable e) {
                takeScreenshot(description.getClassName() +
                               "." + description.getMethodName());
                throw e;
            }
        }
    }

    @Override
    public Statement apply(Statement base, Description description) {
        return new TakeScreenshotStatement(base, description);
    }

    private void takeScreenshot(String name) {
        Date now = new Date();
        SimpleDateFormat dateFormat = new SimpleDateFormat("yyyyMMdd-hhmm");

        try {
            File screenshotsDir = new File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES).getAbsolutePath().toString() +
                                           "/screenshots/");

            if (!screenshotsDir.exists()) {
                if (!screenshotsDir.mkdirs()) {
                    LogUtils.LOGD(TAG, "takeScreenshot: unable to create directory: " +screenshotsDir.toString());
                    return;
                }
            }

            if (!screenshotsDir.canWrite()) {
                LogUtils.LOGD(TAG, "takeScreenshot: unable to write to: " +screenshotsDir.toString());
                return;
            }

            String filename = name + "-" + dateFormat.format(now) + ".jpg";
            File imageFile = new File(screenshotsDir, filename);

            LogUtils.LOGD(TAG, "takeScreenshot: saving to " + screenshotsDir.toString());

            // create bitmap screen capture
            View v1 = getActivity().getWindow().getDecorView().getRootView();
            v1.setDrawingCacheEnabled(true);
            Bitmap bitmap = Bitmap.createBitmap(v1.getDrawingCache());
            v1.setDrawingCacheEnabled(false);

            FileOutputStream outputStream = new FileOutputStream(imageFile);
            int quality = 100;
            bitmap.compress(Bitmap.CompressFormat.JPEG, quality, outputStream);
            outputStream.flush();
            outputStream.close();
        } catch (Throwable e) {
            LogUtils.LOGD(TAG, "takeScreenShot: " + e.getMessage());
            e.printStackTrace();
        }
    }
}
