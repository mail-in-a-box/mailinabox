window.miabldap = window.miabldap || {};

class CaptureConfig {
    static get() {
        return axios.get('/reports/capture/config').then(response => {
            var cc = new CaptureConfig();
            Object.assign(cc, response.data);
            return cc;
        });
    }
};


class UserSettings {
    static load() {
        if (window.miabldap.user_settings) {
            return Promise.resolve(window.miabldap.user_settings);
        }
        
        var s = new UserSettings();
        var json = localStorage.getItem('user_settings');
        if (json) {
            s.data = JSON.parse(json);
        }
        else {
            s.data = {
                row_limit: 1000
            };
        }
        window.miabldap.user_settings = s;
        return Promise.resolve(s);
    }

    static get() {
        return window.miabldap.user_settings;
    }

    save() {
        var json = JSON.stringify(this.data);
        localStorage.setItem('user_settings', json);
    }

    _add_recent(list, val) {
        var found = -1;
        list.forEach((str, idx) => {
            if (str.toLowerCase() == val.toLowerCase()) {
                found = idx;
            }
        });
        if (found >= 0) {
            // move it to the top
            list.splice(found, 1);
        }
        list.unshift(val);
        while (list.length > 10) list.pop();
    }
    

    /* row limit */
    get row_limit() {
        return this.data.row_limit;
    }
    
    set row_limit(v) {
        v = Number(v);
        if (isNaN(v)) {
            throw new ValueError("invalid")
        }
        else if (v < 5) {
            throw new ValueError("minimum 5")
        }
        this.data.row_limit = v;
        this.save();
        return v;
    }

    get_recent_list(name) {
        return this.data['recent_' + name];
    }
    
    add_to_recent_list(name, value) {
        const dataname = 'recent_' + name;
        var v = this.data[dataname];
        if (! v) {
            this.data[dataname] = [ value ];
            this.save();
            return this.data[dataname];
        }
        this._add_recent(v, value);
        this.data[dataname] = v;
        this.save();
        return v;
    }
};
