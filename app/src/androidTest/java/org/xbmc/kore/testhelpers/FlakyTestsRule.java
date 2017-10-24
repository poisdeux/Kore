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


import android.app.Activity;
import android.content.Intent;
import android.graphics.Bitmap;
import android.support.annotation.Nullable;
import android.support.test.rule.ActivityTestRule;
import android.view.View;

import org.junit.runner.Description;
import org.junit.runners.model.Statement;
import org.xbmc.kore.utils.LogUtils;

import java.io.File;
import java.io.FileOutputStream;
import java.io.FilenameFilter;
import java.text.SimpleDateFormat;
import java.util.Date;

public class FlakyTestsRule<T extends Activity> extends ActivityTestRule {
    private final static String TAG = LogUtils.makeLogTag(FlakyTestsRule.class);

    public FlakyTestsRule(Class activityClass) {
        super(activityClass);
    }

    public FlakyTestsRule(Class activityClass, boolean initialTouchMode) {
        super(activityClass, initialTouchMode);
    }

    public FlakyTestsRule(Class activityClass, boolean initialTouchMode, boolean launchActivity) {
        super(activityClass, initialTouchMode, launchActivity);
    }

    @Override
    public Activity launchActivity(@Nullable Intent startIntent) {
        return super.launchActivity(startIntent);
    }

    private class RetryStatement extends Statement {
        private final Statement statement;
        private int retry;
        private int amountOfRetries;
        private final Description description;

        RetryStatement(Statement statement, int retry, Description description) {
            this.statement = statement;
            this.amountOfRetries = retry;
            this.description = description;
        }

        @Override
        public void evaluate() throws Throwable {
            try {
                launchActivity(getActivityIntent());
                statement.evaluate();
                finishActivity();
            } catch (Throwable e) {
                if (retry++ < amountOfRetries) {
                    LogUtils.LOGD(TAG, "Test failed for " + description.getMethodName() +
                                                   " retries left: " + (amountOfRetries - retry));
                    takeScreenshot(description.getClassName() +
                                   "." + description.getMethodName() +
                                   "-" + retry);
                    finishActivity();
                    evaluate();
                } else {
                    finishActivity();
                    throw e;
                }
            }
            //If we get here the test succeeded and we can remove the screenshots
            removeScreenshots(description.getClassName() +
                              "." + description.getMethodName());
        }
    }

    @Override
    public Statement apply(Statement base, Description description) {
        return new RetryStatement(base, 3, description);
    }

    private void finishActivity() {
        Activity activity = getActivity();
        if (activity != null) {
            activity.finish();
            afterActivityFinished();
        }
    }

    /**
     * Removes all screenshots whose filename starts with the given name
     * @param startsWith
     */
    private void removeScreenshots(final String startsWith) {
        try {
            File path = new File(getActivity().getExternalCacheDir().getAbsolutePath() +
                                 "/screenshots/");
            File[] files = path.listFiles(new FilenameFilter() {
                @Override
                public boolean accept(File dir, String name) {
                    return name.startsWith(startsWith);
                }
            });
            if (files == null || files.length == 0)
                return;

            for(File file : files) {
                if (!file.delete()) {
                    LogUtils.LOGD(TAG, "removeScreenshots: failed to delete " + file.getName());
                }
            }
        } catch (Throwable e) {
            LogUtils.LOGD(TAG, "removeScreenshots: " + e.getMessage());
            e.printStackTrace();
        }
    }

    private void takeScreenshot(String name) {
        Date now = new Date();
        SimpleDateFormat dateFormat = new SimpleDateFormat("yyyyMMdd-hhmm");

        try {
            File path = new File(getActivity().getExternalCacheDir().getAbsolutePath() +
                                 "/screenshots/");

            if (!path.exists()) {
                if (!path.mkdirs()) {
                    LogUtils.LOGD(TAG, "takeScreenshot: unable to create directory: " +path.toString());
                    return;
                }
            }

            if (!path.canWrite()) {
                LogUtils.LOGD(TAG, "takeScreenshot: unable to write to: " +path.toString());
                return;
            }

            String filename = name + "-" + dateFormat.format(now) + ".jpg";
            File imageFile = new File(path, filename);

            LogUtils.LOGD(TAG, "takeScreenshot: saving to " + imageFile.toString());

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
