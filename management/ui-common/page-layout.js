/////
///// This file is part of Mail-in-a-Box-LDAP which is released under the
///// terms of the GNU Affero General Public License as published by the
///// Free Software Foundation, either version 3 of the License, or (at
///// your option) any later version. See file LICENSE or go to
///// https://github.com/downtownallday/mailinabox-ldap for full license
///// details.
/////

export default Vue.component('page-layout', function(resolve, reject) {
    axios.get('ui-common/page-layout.html').then((response) => { resolve({

        template: response.data,
        
    })}).catch((e) => {
        reject(e);
    });

});
