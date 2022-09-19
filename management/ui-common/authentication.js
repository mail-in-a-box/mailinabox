/////
///// This file is part of Mail-in-a-Box-LDAP which is released under the
///// terms of the GNU Affero General Public License as published by the
///// Free Software Foundation, either version 3 of the License, or (at
///// your option) any later version. See file LICENSE or go to
///// https://github.com/downtownallday/mailinabox-ldap for full license
///// details.
/////

import { AuthenticationError } from './exceptions.js';


export class Me {
    /* 
     * construct with return value from GET /admin/login or undefined
     * if already logged in
     */
    constructor(me) {
        if (me) {
            Object.assign(this, me);
        }
        else {
            var cred = Me.get_api_credentials();
            if (cred) {
                this.user_id = cred.username;
                this.user_email = cred.username;
                this.session_key = cred.session_key;
            }
        }
    }

    is_authenticated() {
        return true && this.user_id;
    }

    get_email() {
        return this.user_email;
    }

    get_user_id() {
        return this.user_id;
    }

    get_authorization() {
        if (! this.user_id || ! this.session_key) return null;
        return 'Basic ' + window.btoa(this.user_id + ':' + this.session_key);
    }

    /*
     * get api credentials from session storage
     *
     * returns: {
     *    username: String,
     *    session_key: String
     * }
     *
     * or null, if no credentials are in session storage
     */
    static get_api_credentials() {
        var cred = null;
        // code is from templates/index.html for "recall saved user
        // credentials"
        if (typeof sessionStorage != 'undefined' && sessionStorage.getItem("miab-cp-credentials"))
            cred = JSON.parse(sessionStorage.getItem("miab-cp-credentials"));
        else if (typeof localStorage != 'undefined' && localStorage.getItem("miab-cp-credentials"))
            cred = JSON.parse(localStorage.getItem("miab-cp-credentials"));
        return cred;
    }
};


/*
 * axios interceptors for authentication
 */

export function init_authentication_interceptors() {

    // requests: attach non-session based auth (admin panel)
    axios.interceptors.request.use(request => {
        var me = new Me();
        var auth = me.get_authorization();
        if (auth && request.headers.authorization === undefined) {
            request.headers.authorization = auth;
        }
        // prevent daemon.py's @authorized_personnel_only from sending
        // 401 responses, which cause the browser to pop up a
        // credentials dialog box
        request.headers['X-Requested-With'] = 'XMLHttpRequest';
        return request;
    });


    // reponses: handle authorization failures by throwing exceptions
    // users should catch AuthenticationError exceptions
    axios.interceptors.response.use(
        response => {
            if (response.data &&
                response.data.status === 'invalid' &&
                response.config.headers.authorization)
            {
                var url = response.config.url;
                if (response.config.baseURL) {
                    var sep = ( response.config.baseURL.substr(-1) != '/' ?
                                '/' : '' );
                    url = response.config.baseURL + sep + url;
                }
            
                if (url == '/admin/login')
                {
                    // non-flask-session/admin login, which always
                    // returns 200, even for failed logins
                    throw new AuthenticationError(
                        null,
                        'not authenticated',
                        response
                    );
                }
            }
            return response;
        },
        
        error => {
            const auth_required_msg = 'Authentication required - you have been logged out of the server';
            if (! error.response) {
                throw error;
            }
            
            if (error.response.status == 403 &&
                error.response.data == 'login_required')
            {
                // flask session login
                throw new AuthenticationError(error, auth_required_msg);
            }
            else if ((error.response.status == 403 ||
                      error.response.status == 401) &&
                     error.response.data &&
                     error.response.data.status == 'error')
            {
                // admin
                throw new AuthenticationError(error, auth_required_msg);
            }
            throw error;
        }
    );
}

