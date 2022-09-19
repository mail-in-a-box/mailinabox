/////
///// This file is part of Mail-in-a-Box-LDAP which is released under the
///// terms of the GNU Affero General Public License as published by the
///// Free Software Foundation, either version 3 of the License, or (at
///// your option) any later version. See file LICENSE or go to
///// https://github.com/downtownallday/mailinabox-ldap for full license
///// details.
/////

import page_header from '../../ui-common/page-header.js';

export default Vue.component('reports-page-header', {
    props: {
        loading_counter: { type:Number, required:true },
    },
    
    components: {
        'page-header': page_header,
    },
    
    template:
    '<page-header '+
        'header_text="Server Activity" :loading_counter="loading_counter">'+
        '<template v-slot:links>'+
        '  <b-navbar type="dark" variant="transparent" class="p-0">'+
        '    <b-navbar-nav>'+
        '      <b-nav-item href="/admin">Admin Panel</b-nav-item>'+
        '      <b-nav-item to="/settings"><b-icon icon="gear-fill" aria-hidden="true"></b-icon></b-nav-item>'+
        '    </b-navbar-nav>'+
        '  </b-navbar>'+
        '</template>'+
        '</page-header>'
    ,
    
});
