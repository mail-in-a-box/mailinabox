#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

from selenium.webdriver import (
    Chrome,
    ChromeOptions,
    Firefox,
    FirefoxOptions
)
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.remote.webelement import WebElement
from selenium.webdriver.common.by import By
from selenium.common.exceptions import (
    NoSuchElementException,
    TimeoutException,
    ElementNotInteractableException
)

import os
import subprocess
import time


#
# chrome:
#    snap install chromium
#
# firefox:
#    apt-get install firefox
#    get the latest compiled geckodriver from:
#        https://github.com/mozilla/geckodriver/releases
#    copy into /usr/local/bin
#
# all:
#    pip3 install selenium (python 3.7 is required by selenium)
#

# OLD: for headless firefox (before firefox supported headless)
#    apt-get -y install xorg xvfb gtk2-engines-pixbuf
#    apt-get -y install dbus-x11 xfonts-base xfonts-100dpi xfonts-75dpi xfonts-cyrillic xfonts-scalable
#    apt-get -y install imagemagick x11-apps
#
#    before running tests, create an X frame buffer display:
#       Xvfb -ac :99 -screen 0 1280x1024x16 & export DISPLAY=:99
#


class ChromeTestDriver(Chrome):
    def __init__(self, options=None):
        '''Initialze headless chrome. If problems arise, try running from the
           command line: `chromium --headless http://localhost/mail/`

        '''
        if not options:
            options = ChromeOptions()
            options.headless = True
            
            # set a window size
            options.add_argument("--window-size=1200x600")
            
            # deal with ssl certificates since chrome has its own
            # trusted ca list and does not use the system's
            options.add_argument('--allow-insecure-localhost')
            options.add_argument('--ignore-certificate-errors')

            # required to run chromium as root
            options.add_argument('--no-sandbox')
            
        super(ChromeTestDriver, self).__init__(
            executable_path='/snap/bin/chromium.chromedriver',
            options=options
        )

        self.delete_all_cookies()


class FirefoxTestDriver(Firefox):
    ''' TODO: untested '''
    def __init__(self, options=None):
        if not options:
            options = FirefoxOptions()
            options.headless = True
            
        super(FirefoxTestDriver, self).__init__(
            executable_path='/usr/local/bin/geckodriver',
            options=options
        )

        self.delete_all_cookies()


class TestDriver(object):
    def __init__(self, driver=None, verbose=None, base_url=None, output_path=None):
        self.first_start_time = None
        self.start_time = None
        self.start_msg = []
        self.next_tick_id = 0
        
        if driver is None:
            if 'BROWSER_TESTS_BROWSER' in os.environ:
                driver = os.environ['BROWSER_TESTS_BROWSER']
            else:
                driver = 'chrome'
        if isinstance(driver, str):
            driver = TestDriver.createByName(driver)
        self.driver = driver
        
        if verbose is None:
            if 'BROWSER_TESTS_VERBOSITY' in os.environ:
                verbose = int(os.environ['BROWSER_TESTS_VERBOSITY'])
            else:
                verbose = 1
        self.verbose = verbose
        
        if base_url is None:
            if 'BROWSER_TESTS_BASE_URL' in os.environ:
                base_url = os.environ['BROWSER_TESTS_BASE_URL']
            else:
                hostname = subprocess.check_output(['/bin/hostname','--fqdn'])
                base_url = "https://%s" % hostname.decode('utf-8').strip()
        self.base_url = base_url

        if output_path is None:
            if 'BROWSER_TESTS_OUTPUT_PATH' in os.environ:
                output_path = os.environ['BROWSER_TESTS_OUTPUT_PATH']
            else:
                output_path= "./"
        self.output_path = output_path

        

    @staticmethod
    def createByName(name):
        if name == 'chrome':
            return ChromeTestDriver()
        elif name == 'firefox':
            return FirefoxTestDriver()
        raise ValueError('no such driver named "%s"' % name)

    def _say(self, loglevel, heirarchy_level, *args):
        if self.verbose >= loglevel:
            for i in range(len(self.start_msg), heirarchy_level+1):
                self.start_msg.append(None)
            self.start_msg = self.start_msg[0:heirarchy_level]
            indent = 0
            for item in self.start_msg:
                if item is not None: indent += 1
            msg = args[0] % (args[1:])
            self.start_msg.append(msg)
            print('  '*indent + msg + ' ')
            
            
    def is_verbose(self):
        return self.verbose >= 2
        
    def say_verbose(self, *args):
        self._say(2, 2, *args)

    def say(self, *args):
        self._say(1, 1, *args)

    def start(self, *args):
        now = time.time()
        if self.start_time is not None:
            elapsed = format(now - self.start_time, '.1f')
            self._say(2, 0, '[%s: %s seconds]\n', self.start_msg[0], elapsed)
        else:
            self.first_start_time = now
        self.start_time = now
        self._say(1, 0, *args)
    
    def last_start(self):
        msg = []
        for item in self.start_msg:
            if item is not None: msg.append(item)
        return " / ".join(msg)

    
    def get(self, url):
        ''' load a web page in the current browser session '''
        if not url.startswith('http'):
            url = self.base_url + url
        self.say_verbose('get %s', url)
        self.driver.get(url)
        return self

    def title(self):
        return self.driver.title

    def current_url(self):
        return self.driver.current_url

    def refresh(self):
        self.driver.refresh()
        return self

    def get_current_window_handle(self):
        ''' returns the string id of the current window/tab '''
        return self.driver.current_window_handle
    
    def get_window_handles(self):
        ''' returns an array of strings, one for each window or tab open '''
        return self.driver.window_handles

    def switch_to_window(self, handle):
        ''' returns the current window handle '''
        cur = self.get_current_window_handle()
        self.driver.switch_to.window(handle)
        return cur

    def switch_to_frame(self, iframe_el):
        self.driver.switch_to.frame(iframe_el.el)

    def switch_to_parent_frame(self, iframe_el):
        # untested
        self.driver.switch_to.parent_frame(iframe_el.el)

    def save_screenshot(self, where, ignore_errors=False, quiet=True):
        ''' where - path and file name of screen shotfile 
            eg: "out/screenshot.png". '''
        if not where.startswith('/'):
            where = os.path.join(self.output_path, where)
        try:
            os.makedirs(os.path.dirname(where), exist_ok=True)
            self._say(1 if quiet else 2, 2, "save screenshot: '%s'", where)
            self.driver.save_screenshot(where)
        except Exception as e:
            if not ignore_errors:
                raise e

    def delete_cookie(self, name):
        self.driver.delete_cookie(name)
            
    def wait_for_id(self, id, secs=5, throws=True):
        return self.wait_for_el('#' + id, secs=secs, throws=throws)

    def wait_for_el(self, css_selector, secs=5, throws=True, must_be_enabled=False, must_be_displayed=None):
        msg=[]
        if must_be_enabled:
            msg.append('enabled')
        if must_be_displayed is True:
            msg.append('displayed')
        elif must_be_displayed is False:
            msg.append('hidden')
        if len(msg)==0:
            self.say_verbose("wait for selector '%s' (%ss)",
                             css_selector, secs)
        else:
            self.say_verbose("wait for selector '%s' to be %s (%ss)",
                             css_selector, ",".join(msg), secs)
        def test_fn(driver):
            found_el = driver.find_element(By.CSS_SELECTOR, css_selector)
            if must_be_enabled and not found_el.is_enabled():
                raise NoSuchElementException()
            if must_be_displayed is not None:
                if must_be_displayed and not found_el.is_displayed():
                    raise NoSuchElementException()
                if not must_be_displayed and found_el.is_displayed():
                    raise NoSuchElementException()                
            return found_el
        wait = WebDriverWait(self.driver, secs, ignored_exceptions= (
            NoSuchElementException
        ))
        try:
            rtn = wait.until(test_fn)
            return ElWrapper(self, rtn)
        except TimeoutException as e:
            if throws: raise e
            else: return None

    def wait_for_el_not_exists(self, css_selector, secs=5, throws=True):
        self.say_verbose("wait for selector '%s' (%ss) to not exist",
                             css_selector, secs)
        def test_fn(driver):
            found_el = driver.find_element(By.CSS_SELECTOR, css_selector)
            if found_el: raise NoSuchElementException()
        wait = WebDriverWait(self.driver, secs, ignored_exceptions= (
            NoSuchElementException
        ))
        try:
            wait.until(test_fn)
            return True
        except TimeoutException as e:
            if throws: raise e
            else: return None

    def wait_for_text(self, text, tag='*', secs=5, exact=False, throws=True, case_sensitive=False):
        self.say_verbose("wait for text '%s'", text)
        def test_fn(driver):
            return self.find_text(text, tag=tag, exact=exact, throws=False, quiet=True, case_sensitive=case_sensitive)
        wait = WebDriverWait(self.driver, secs, ignored_exceptions= (
            NoSuchElementException
        ))
        try:
            rtn = wait.until(test_fn)
            return rtn
        except TimeoutException as e:
            if throws: raise e
            else: return None

    def find_el(self, css_selector, nth=0, throws=True, quiet=False):
        try:
            els = self.driver.find_elements(By.CSS_SELECTOR, css_selector)
            if len(els)==0:
                if not quiet: self.say_verbose("find element: '%s' (not found)", css_selector)
                raise NoSuchElementException("selector=%s" % css_selector)
            if not quiet: self.say_verbose("find element: '%s' (returning #%s/%s)", css_selector, nth+1, len(els))
            return ElWrapper(self, els[nth])
        except (IndexError, NoSuchElementException) as e:
            if throws: raise e
            else: return None

    def find_els(self, css_selector, throws=True, displayed=False):
        self.say_verbose("find elements: '%s'", css_selector)
        try:
            els = self.driver.find_elements(By.CSS_SELECTOR, css_selector)
            return [ ElWrapper(self, el) for el in els if not displayed or el.is_displayed() ]
        except (IndexError, NoSuchElementException) as e:
            if throws: raise e
            else: return None

    def find_text(self, text, tag='*', exact=False, throws=True, quiet=False, case_sensitive=False):
        if not quiet:
            self.say_verbose("find text: '%s' tag=%s exact=%s",
                             text, tag, exact)
        try:
            if exact:
                if case_sensitive:
                    xpath = "//%s[normalize-space(text()) = '%s']" % (tag, text)
                else:
                    uc = text.upper()
                    lc = text.lower()
                    xpath = "//%s[normalize-space(translate(text(), '%s', '%s')) = '%s']" % (tag, lc, uc, uc)
            else:
                if case_sensitive:
                    xpath = "//%s[contains(text(),'%s')]" % (tag, text)
                else:
                    uc = text.upper()
                    lc = text.lower()
                    xpath = "//%s[contains(translate(text(),'%s','%s'),'%s')]" % (tag, lc, uc, uc)

            el = self.driver.find_element(by=By.XPATH, value=xpath)
            return ElWrapper(self, el)
        except NoSuchElementException as e:
            if throws: raise e
            else: return None

    def sleep(self, secs):
        self.say_verbose('sleep %s secs', secs)
        def test_fn(driver):
            raise NoSuchElementException
        wait = WebDriverWait(self.driver, secs, ignored_exceptions= (
            NoSuchElementException
        ))
        try:
            wait.until(test_fn)
        except TimeoutException as e:
            pass

    def execute_script(self, script, quiet=False, *args):
        ''' Synchronously Executes JavaScript in the current window/frame '''
        newargs = []
        for arg in args:
            if isinstance(arg, ElWrapper): newargs.append(arg.el)
            else: newargs.append(arg)
        if not quiet:
            self.say_verbose('execute script: %s', script.replace('\n',' '))
        return self.driver.execute_script(script, *newargs)

    def execute_async_script(self, script, secs=5, *args):
        ''' Asynchronously Executes JavaScript in the current window/frame '''
        self.driver.set_script_timeout(secs)
        self.driver.execute_async_script(script, *args)

    def wait_until_true(self, script, secs=5, *args):
        self.say_verbose('run script until true: %s', script)
        d = self
        class NotTrue(Exception):
            pass
        def test_fn(driver):
            nonlocal script, args
            p = driver.execute_script(script, quiet=True, *args)
            driver.say_verbose("script returned: %s", p)
            if not p: raise NotTrue()
            return True
        wait = WebDriverWait(self, secs, ignored_exceptions= (
            NotTrue
        ))
        wait.until(test_fn)  # throws TimeoutException

    def wait_tick(self, delay_ms, secs=5):
        # allow time for vue to render (delay_ms>=1)
        cancel_id = self.execute_script('window.qa_ticked=false; return window.setTimeout(() => { window.qa_ticked=true; }, %s)' % delay_ms);
        self.wait_until_true('return window.qa_ticked === true', secs=secs)
    
    def close(self):
        ''' close the window/tab '''
        self.say_verbose("closing %s", self.driver.current_url)
        self.driver.close()

    def quit(self):
        ''' closes the browser and shuts down the chromedriver executable '''
        now = time.time()
        if self.first_start_time is not None:
            elapsed = format(now - self.first_start_time, '.1f')
            self._say(2, 0, '[TOTAL TIME: %s seconds]\n', elapsed)
        self.driver.quit()

    def fail(self, exception):
        last_start = self.last_start()
        self.start("Failure!")
        self.save_screenshot('screenshot.png', ignore_errors=False, quiet=False)
        if hasattr(exception, 'msg') and exception.msg != '':
            exception.msg = "Error during '%s': %s" % (last_start, exception.msg)
        else:
            exception.msg = "Error during '%s'" % last_start

    


class ElWrapper(object):
    '''see:
        https://github.com/SeleniumHQ/selenium/blob/trunk/py/selenium/webdriver/remote/webelement.py

    '''
    def __init__(self, driver, el):
        self.driver = driver
        self.el = el

    def find_el(self, css_selector, nth=0, throws=True, quiet=False):
        try:
            els = self.el.find_elements(By.CSS_SELECTOR, css_selector)
            if len(els)==0:
                if not quiet: self.driver.say_verbose("find element: '%s' (not found)", css_selector)
                raise NoSuchElementException("selector=%s" % css_selector)
            if not quiet: self.driver.say_verbose("find element: '%s' (returning #%s/%s)", css_selector, nth+1, len(els))
            return ElWrapper(self.driver, els[nth])
        except (IndexError, NoSuchElementException) as e:
            if throws: raise e
            else: return None

    def find_els(self, css_selector, throws=True, displayed=False):
        self.driver.say_verbose("find elements: '%s'", css_selector)
        try:
            els = self.el.find_elements(By.CSS_SELECTOR, css_selector)
            return [ ElWrapper(self.driver, el) for el in els if not displayed or el.is_displayed() ]
        except (IndexError, NoSuchElementException) as e:
            if throws: raise e
            else: return None
    
    def is_enabled(self):
        return self.el.is_enabled()

    def is_checked(self):
        """ a checkbox or radio button is checked """
        return self.el.is_selected()

    def is_displayed(self):
        """Whether the self.element is visible to a user."""
        return self.el.is_displayed()
    
    def get_attribute(self, name):
        return self.el.get_attribute(name)

    def get_property(self, expr):
        self.driver.say_verbose('get property %s', expr)
        prefix = '.'
        if expr.startswith('.') or expr.startswith('['): prefix=''
        p = self.driver.execute_script(
            "return arguments[0]%s%s;" % ( prefix, expr ),
            self.el
        )
        if isinstance(p, WebElement):
            p = ElWrapper(self.driver, p)
        if isinstance(p, bool):
            self.driver.say_verbose('property result: %s', p)
        else:
            self.driver.say_verbose('property result: %s', p.__class__)
        return p

    def content(self, max_length=None, ellipses=True):
        txt = self.el.text
        if not max_length or len(txt)<max_length:
            return txt
        if ellipses:
            return txt[0:max_length] + '...'
        return txt[0:max_length]

    def tag(self):
        return self.el.tag_name

    def location(self):
        """ returns dictionary {x:N, y:N} """
        return self.el.location()

    def rect(self):
        return self.el.rect()

    def parent(self):
        # get the parent element
        p = self.driver.execute_script(
            "return arguments[0].parentNode;",
            self.el
        )
        return ElWrapper(self.driver, p)
    
    def send_text(self, *value):
        self.driver.say_verbose("send text '%s'", "/".join(value))
        self.send_keys(*value)
        return self
        
    def send_keys(self, *value):
        self.el.send_keys(*value)
        return self

    def clear_text(self):
        self.el.clear()
        return self

    def click(self):
        if self.driver.is_verbose():
            content = self.content(max_length=40).replace('\n',' ').strip()
            tag = self.tag()
            if tag=='a':
                tag='link'
                if content == '': content=self.get_attribute('href')
            if content != '':
                self.driver.say_verbose("click %s '%s'", tag, content)
            else:
                self.driver.say_verbose("click %s", tag)            
        self.el.click()
        return self

        


#dir(el)
#['__abstractmethods__', '__class__', '__delattr__', '__dict__', '__dir__', '__doc__', '__eq__', '__format__', '__ge__', '__getattribute__', '__gt__', '__hash__', '__init__', '__init_subclass__', '__le__', '__lt__', '__module__', '__ne__', '__new__', '__reduce__', '__reduce_ex__', '__repr__', '__setattr__', '__sizeof__', '__str__', '__subclasshook__', '__weakref__', '_abc_impl', '_execute', '_id', '_parent', '_upload', 'accessible_name', 'aria_role', 'clear', 'click', 'find_element', 'find_elements', 'get_attribute', 'get_dom_attribute', 'get_property', 'id', 'is_displayed', 'is_enabled', 'is_selected', 'location', 'location_once_scrolled_into_view', 'parent', 'rect', 'screenshot', 'screenshot_as_base64', 'screenshot_as_png', 'send_keys', 'shadow_root', 'size', 'submit', 'tag_name', 'text', 'value_of_css_property']

        
#dir(driver)
#['__abstractmethods__', '__class__', '__delattr__', '__dict__', '__dir__', '__doc__', '__enter__', '__eq__', '__exit__', '__format__', '__ge__', '__getattribute__', '__gt__', '__hash__', '__init__', '__init_subclass__', '__le__', '__lt__', '__module__', '__ne__', '__new__', '__reduce__', '__reduce_ex__', '__repr__', '__setattr__', '__sizeof__', '__str__', '__subclasshook__', '__weakref__', '_abc_impl', '_authenticator_id', '_file_detector', '_get_cdp_details', '_is_remote', '_mobile', '_shadowroot_cls', '_switch_to', '_unwrap_value', '_web_element_cls', '_wrap_value', 'add_cookie', 'add_credential', 'add_virtual_authenticator', 'application_cache', 'back', 'bidi_connection', 'capabilities', 'caps', 'close', 'command_executor', 'create_options', 'create_web_element', 'current_url', 'current_window_handle', 'delete_all_cookies', 'delete_cookie', 'delete_network_conditions', 'desired_capabilities', 'error_handler', 'execute', 'execute_async_script', 'execute_cdp_cmd', 'execute_script', 'file_detector', 'file_detector_context', 'find_element', 'find_elements', 'forward', 'fullscreen_window', 'get', 'get_cookie', 'get_cookies', 'get_credentials', 'get_issue_message', 'get_log', 'get_network_conditions', 'get_pinned_scripts', 'get_screenshot_as_base64', 'get_screenshot_as_file', 'get_screenshot_as_png', 'get_sinks', 'get_window_position', 'get_window_rect', 'get_window_size', 'implicitly_wait', 'launch_app', 'log_types', 'maximize_window', 'minimize_window', 'mobile', 'name', 'orientation', 'page_source', 'pin_script', 'pinned_scripts', 'port', 'print_page', 'quit', 'refresh', 'remove_all_credentials', 'remove_credential', 'remove_virtual_authenticator', 'save_screenshot', 'service', 'session_id', 'set_network_conditions', 'set_page_load_timeout', 'set_permissions', 'set_script_timeout', 'set_sink_to_use', 'set_user_verified', 'set_window_position', 'set_window_rect', 'set_window_size', 'start_client', 'start_desktop_mirroring', 'start_session', 'start_tab_mirroring', 'stop_casting', 'stop_client', 'switch_to', 'timeouts', 'title', 'unpin', 'vendor_prefix', 'virtual_authenticator_id', 'window_handles']

