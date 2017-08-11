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

package org.xbmc.kore.tests.ui;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.support.test.espresso.Espresso;
import android.support.test.rule.ActivityTestRule;
import android.support.test.runner.AndroidJUnit4;
import android.support.v7.app.AppCompatActivity;
import android.support.v7.preference.PreferenceManager;
import android.view.View;

import org.junit.After;
import org.junit.AfterClass;
import org.junit.Before;
import org.junit.BeforeClass;
import org.junit.Ignore;
import org.junit.Rule;
import org.junit.rules.TestWatcher;
import org.junit.runner.Description;
import org.junit.runner.RunWith;
import org.xbmc.kore.host.HostInfo;
import org.xbmc.kore.jsonrpc.HostConnection;
import org.xbmc.kore.testhelpers.LoaderIdlingResource;
import org.xbmc.kore.testhelpers.Utils;
import org.xbmc.kore.testutils.Database;
import org.xbmc.kore.testutils.tcpserver.MockTcpServer;
import org.xbmc.kore.testutils.tcpserver.handlers.AddonsHandler;
import org.xbmc.kore.testutils.tcpserver.handlers.ApplicationHandler;
import org.xbmc.kore.testutils.tcpserver.handlers.InputHandler;
import org.xbmc.kore.testutils.tcpserver.handlers.JSONConnectionHandlerManager;
import org.xbmc.kore.testutils.tcpserver.handlers.JSONRPCHandler;
import org.xbmc.kore.testutils.tcpserver.handlers.PlayerHandler;
import org.xbmc.kore.ui.sections.hosts.HostFragmentManualConfiguration;
import org.xbmc.kore.utils.LogUtils;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.Date;

@RunWith(AndroidJUnit4.class)
@Ignore
abstract public class AbstractTestClass<T extends AppCompatActivity> {
    private static final String TAG = LogUtils.makeLogTag(AbstractTestClass.class);

    abstract protected ActivityTestRule<T> getActivityTestRule();

    /**
     * Method that can be used to change the shared preferences.
     * This will be called before each test after clearing the settings
     * in {@link #setUp()}
     */
    abstract protected void setSharedPreferences(Context context);

    /**
     * Called from {@link #setUp()} right after HostInfo has been created.
     * @param hostInfo created HostInfo used by the activity under test
     */
    abstract protected void configureHostInfo(HostInfo hostInfo);

    private LoaderIdlingResource loaderIdlingResource;
    private ActivityTestRule<T> activityTestRule;
    private static MockTcpServer server;
    private static JSONConnectionHandlerManager manager;
    private AddonsHandler addonsHandler;
    private static PlayerHandler playerHandler;
    private static ApplicationHandler applicationHandler;
    private static InputHandler inputHandler;

    private Activity activity;
    private HostInfo hostInfo;

    @Rule
    public TestWatcher watchman = new TestWatcher() {
        @Override
        protected void failed(Throwable e, Description description) {
            takeScreenshot(description.getClassName() + "." + description.getMethodName());
        }

        @Override
        protected void succeeded(Description description) {

        }
    };

    @BeforeClass
    public static void setupMockTCPServer() throws Throwable {
        playerHandler = new PlayerHandler();
        applicationHandler = new ApplicationHandler();
        inputHandler = new InputHandler();
        manager = new JSONConnectionHandlerManager();
        manager.addHandler(playerHandler);
        manager.addHandler(applicationHandler);
        manager.addHandler(inputHandler);
        manager.addHandler(new JSONRPCHandler());
        server = new MockTcpServer(manager);
        server.start();
    }

    @Before
    public void setUp() throws Throwable {

        activityTestRule = getActivityTestRule();

        final Context context = activityTestRule.getActivity();
        if (context == null)
            throw new RuntimeException("Could not get context. Maybe activity failed to start?");

        Utils.clearSharedPreferences(context);
        //Prevent drawer from opening when we start a new activity
        Utils.setLearnedAboutDrawerPreference(context, true);
        //Allow each test to change the shared preferences
        setSharedPreferences(context);

        activity = getActivity();

        //Note: as the activity is not yet available in @BeforeClass we need
        //      to add the handler here
        if (addonsHandler == null) {
            addonsHandler = new AddonsHandler(context);
            manager.addHandler(addonsHandler);
        }

        SharedPreferences prefs = PreferenceManager.getDefaultSharedPreferences(context);
        boolean useEventServer = prefs.getBoolean(HostFragmentManualConfiguration.HOST_USE_EVENT_SERVER, false);

        hostInfo = Database.addHost(context, server.getHostName(),
                                    HostConnection.PROTOCOL_TCP, HostInfo.DEFAULT_HTTP_PORT,
                                    server.getPort(), useEventServer);
        //Allow each test to change the host info
        configureHostInfo(hostInfo);

        loaderIdlingResource = new LoaderIdlingResource(activityTestRule.getActivity().getSupportLoaderManager());
        Espresso.registerIdlingResources(loaderIdlingResource);

        Utils.disableAnimations(context);

        Utils.setupMediaProvider(context);

        Database.fill(hostInfo, context, context.getContentResolver());

        Utils.switchHost(context, activityTestRule.getActivity(), hostInfo);

        //Relaunch the activity for the changes (Host selection, preference changes, and database fill) to take effect
        activityTestRule.launchActivity(new Intent());
    }

    @After
    public void tearDown() throws Exception {
        if ( loaderIdlingResource != null )
            Espresso.unregisterIdlingResources(loaderIdlingResource);

        applicationHandler.reset();
        playerHandler.reset();

        Context context = activityTestRule.getActivity();
        Database.flush(context.getContentResolver(), hostInfo);
        Utils.enableAnimations(context);
    }

    @AfterClass
    public static void cleanup() throws IOException {
        server.shutdown();
    }

    protected T getActivity() {
        if (activityTestRule != null) {
            return activityTestRule.getActivity();
        }
        return null;
    }

    public static PlayerHandler getPlayerHandler() {
        return playerHandler;
    }

    public static ApplicationHandler getApplicationHandler() {
        return applicationHandler;
    }

    public static InputHandler getInputHandler() {
        return inputHandler;
    }

    protected void takeScreenshot(String name) {
        Date now = new Date();
        SimpleDateFormat dateFormat = new SimpleDateFormat("yyyyMMdd-hhmm");

        try {
            File path = new File(activity.getExternalCacheDir().getAbsolutePath() +
                                 "/screenshots/");

            if (!path.exists()) {
                if (!path.mkdirs()) {
                    LogUtils.LOGD("AbstractTestClass", "takeScreenshot: unable to create directory: " +path.toString());
                    return;
                }
            }

            if (!path.canWrite()) {
                LogUtils.LOGD("AbstractTestClass", "takeScreenshot: unable to write to: " +path.toString());
                return;
            }

            String filename = name + "-" + dateFormat.format(now) + ".jpg";
            File imageFile = new File(path, filename);

            LogUtils.LOGD("AbstractTestClass", "takeScreenshot: saving to " + imageFile.toString());

            // create bitmap screen capture
            View v1 = activity.getWindow().getDecorView().getRootView();
            v1.setDrawingCacheEnabled(true);
            Bitmap bitmap = Bitmap.createBitmap(v1.getDrawingCache());
            v1.setDrawingCacheEnabled(false);

            FileOutputStream outputStream = new FileOutputStream(imageFile);
            int quality = 100;
            bitmap.compress(Bitmap.CompressFormat.JPEG, quality, outputStream);
            outputStream.flush();
            outputStream.close();
        } catch (Throwable e) {
            LogUtils.LOGD("AbstractTestClass", "takeScreenShot: " + e.getMessage());
            e.printStackTrace();
        }
    }
}
