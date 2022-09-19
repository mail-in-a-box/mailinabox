/////
///// This file is part of Mail-in-a-Box-LDAP which is released under the
///// terms of the GNU Affero General Public License as published by the
///// Free Software Foundation, either version 3 of the License, or (at
///// your option) any later version. See file LICENSE or go to
///// https://github.com/downtownallday/mailinabox-ldap for full license
///// details.
/////

var spinner = Vue.component('spinner', {
    template: '<span class="spinner-border spinner-border-sm"></span>'
});

var header = Vue.component('page-header', function(resolve, reject) {
    axios.get('ui-common/page-header.html').then((response) => { resolve({

        props: {
            header_text: { type: String, required: true },
            loading_counter: { type: Number, required: true }
        },
        
        template: response.data
                        
    })}).catch((e) => {
        reject(e);
    });

});

export { spinner, header as default };
