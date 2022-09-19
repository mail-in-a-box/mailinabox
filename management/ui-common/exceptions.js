/////
///// This file is part of Mail-in-a-Box-LDAP which is released under the
///// terms of the GNU Affero General Public License as published by the
///// Free Software Foundation, either version 3 of the License, or (at
///// your option) any later version. See file LICENSE or go to
///// https://github.com/downtownallday/mailinabox-ldap for full license
///// details.
/////

export class ValueError extends Error {
    constructor(msg) {
        super(msg);
    }
};

export class AssertionError extends Error {
}

export class AuthenticationError extends Error {
    constructor(caused_by_error, msg, response) {
        super(msg);
        this.caused_by = caused_by_error;
        this.response = response;
        if (!response && caused_by_error)
            this.response = caused_by_error.response;
    }
};
