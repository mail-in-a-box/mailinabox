/////
///// This file is part of Mail-in-a-Box-LDAP which is released under the
///// terms of the GNU Affero General Public License as published by the
///// Free Software Foundation, either version 3 of the License, or (at
///// your option) any later version. See file LICENSE or go to
///// https://github.com/downtownallday/mailinabox-ldap for full license
///// details.
/////

import { spinner } from "../../ui-common/page-header.js";

export default Vue.component('message-headers-view', {
    props: {
        lmtp_id: String,
        user_id: String
    },
    
    template:
    '<div>' +
        '<div class="text-center" v-if="loading">{{loading_msg}} <spinner></spinner></div>' +
        '<pre v-else>{{ message_headers }}</pre>' +
        '</div>',

    data: function() {
        return {
            loading: true,
            loading_msg: '',
            message_headers: ''
        }
    },

    watch: {
        lmtp_id: function() {
            this.load(this.lmtp_id, this.user_id);
        }
    },

    mounted: function() {
        this.load(this.lmtp_id, this.user_id);
    },

    methods: {
        load: function(lmtp_id, user_id) {
            if (!lmtp_id || !user_id) {
                this.message_headers = 'no data';
                return;
            }
            this.loading = true;
            this.loading_msg = 'Searching for message with LMTP ID ' + lmtp_id;
            axios.post('reports/uidata/message-headers', {
                lmtp_id,
                user_id
            }).then(response => {
                this.message_headers = response.data;
                if (this.message_headers == '')
                    this.message_headers = `Message with LMTP "${lmtp_id}" not found. It may have been deleted.`;
            }).catch(e => {
                this.message_headers = '' + (e.response.data || e);
            }).finally( () => {
                this.loading = false;
            });
        }
    }
    
});

