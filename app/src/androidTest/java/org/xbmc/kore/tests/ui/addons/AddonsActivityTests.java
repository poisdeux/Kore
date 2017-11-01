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

package org.xbmc.kore.tests.ui.addons;

import android.content.Intent;
import android.support.test.rule.ActivityTestRule;
import android.widget.TextView;

import org.junit.Before;
import org.junit.Rule;
import org.junit.Test;
import org.xbmc.kore.R;
import org.xbmc.kore.testhelpers.EspressoTestUtils;
import org.xbmc.kore.tests.ui.AbstractTestClass;
import org.xbmc.kore.tests.ui.BaseMediaActivityTests;
import org.xbmc.kore.ui.sections.addon.AddonsActivity;
import org.xbmc.kore.ui.sections.video.MoviesActivity;

import static android.support.test.espresso.Espresso.onView;
import static android.support.test.espresso.assertion.ViewAssertions.matches;
import static android.support.test.espresso.matcher.ViewMatchers.withId;
import static android.support.test.espresso.matcher.ViewMatchers.withParent;
import static android.support.test.espresso.matcher.ViewMatchers.withText;
import static junit.framework.Assert.fail;
import static org.hamcrest.Matchers.allOf;
import static org.hamcrest.Matchers.instanceOf;
import static org.xbmc.kore.testhelpers.EspressoTestUtils.selectListItemPressBackAndCheckActionbarTitle;

/**
 *
 * AddonsActivity doesn't use the local database to get a list of addons. But
 * consults Kodi each time it is started.
 * With Espresso this results in a deadlock situation as it waits for the activity to become
 * idle which it never will.
 *
 * Normal startup procedure would be as follows:
 *
 * 1. Start MockTCPServer {@link AbstractTestClass#setupMockTCPServer()}
 * 2. Start AddonsActivity {mActivityRule}
 * 3. Espresso waits for activity to become idle before calling {@link AbstractTestClass#setUp()}
 * 4. Add AddonsHandler {@link AbstractTestClass#setUp()}
 *
 * At step 2 the AddonsActivity displays an animated progress indicator while it waits for the
 * MockTCPServer to send the list of addons.
 * This is never send as the {@link org.xbmc.kore.testutils.tcpserver.handlers.AddonsHandler} is
 * added in {@link super#setUp()} which is never started by Espresso as it waits for
 * {@link org.xbmc.kore.ui.sections.addon.AddonsActivity} to become idle.
 *
 * We therefore first start another activity (MoviesActivity) from which we start the AddonsActivity.
 */
public class AddonsActivityTests extends BaseMediaActivityTests<MoviesActivity> {

    /**
     * Note: we use MoviesActivity here instead of AddonsActivity. See above comment to know why
     */
    @Rule
    public ActivityTestRule<MoviesActivity> mActivityRule = new ActivityTestRule<>(
            MoviesActivity.class);

    @Override
    protected android.support.test.rule.ActivityTestRule getActivityTestRule() {
        return mActivityRule;
    }

    @Before
    @Override
    public void setUp() throws Throwable {
        super.setUp();

        Intent intent = new Intent(getActivity(), AddonsActivity.class);
        getActivity().startActivity(intent);
    }


    /**
     * Test if action bar title initially displays Addons
     */
    @Test
    public void setActionBarTitleMain() {
        onView(allOf(instanceOf(TextView.class), withParent(withId(R.id.default_toolbar))))
                .check(matches(withText(R.string.addons)));
        fail();
    }

    /**
     * Test if action bar title is correctly set after selecting a list item
     *
     * UI interaction flow tested:
     *   1. Click on list item
     *   2. Result: action bar title should show list item title
     */
    @Test
    public void setActionBarTitle() {
        EspressoTestUtils.selectListItemAndCheckActionbarTitle(0, R.id.list,
                                                               "Dumpert");
    }

    /**
     * Test if action bar title is correctly restored after a configuration change
     *
     * UI interaction flow tested:
     *   1. Click on list item
     *   2. Rotate device
     *   3. Result: action bar title should show list item title
     */
    @Test
    public void restoreActionBarTitleOnConfigurationStateChanged() {
        EspressoTestUtils.selectListItemRotateDeviceAndCheckActionbarTitle(0, R.id.list,
                                                                           "Dumpert",
                                                                           getActivity());
    }

    /**
     * Test if action bar title is correctly restored after returning from a movie selection
     *
     * UI interaction flow tested:
     *   1. Click on list item
     *   2. Press back
     *   3. Result: action bar title should show main title
     */
    @Test
    public void restoreActionBarTitleOnReturningFromMovie() {
        selectListItemPressBackAndCheckActionbarTitle(0, R.id.list,
                                                      getActivity().getString(R.string.addons));
    }
}
