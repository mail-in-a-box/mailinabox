/*
  details on the activity of a user
*/

import wbr_text from "./wbr-text.js";
import chart_table from "./chart-table.js";
import message_headers_view from "./message_headers_view.js";
import UserSettings from "./settings.js";
import { BvTable, MailBvTable, ConnectionDisposition } from "./charting.js";


export default Vue.component('panel-user-activity', function(resolve, reject) {
    axios.get('reports/ui/panel-user-activity.html').then((response) => { resolve({

        template: response.data,
        
        props: {
            date_range: Array,  // YYYY-MM-DD strings (UTC)
        },

        components: {
            'wbr-text': wbr_text,
            'message-headers-view': message_headers_view,
            'chart-table': chart_table,
        },
        
        data: function() {
            var start_tab = this.$route.query.tab ?
                Number(this.$route.query.tab) :
                0;
            return {
                //user_id: this.$route.query.user || '', /* v-model */
                user_id: '', /* v-model */
                tab_index: start_tab, /* v-model */
                show_only_flagged: false,
                show_only_flagged_filter: null,
                data_user_id: null, /* user_id for active table data */
                data_date_range: null, /* date range for active table data */
                sent_mail: null,
                received_mail: null,
                imap_conn_summary: null,
                imap_details: null,
                lmtp_id: null, /* for message headers modal */
                all_users: [],
                disposition_formatter: ConnectionDisposition.formatter,
            };
        },

        activated: function() {
            const new_tab = Number(this.$route.query.tab);
            const new_user = this.$route.query.user;
            
            if (new_user && new_user != this.user_id) {
                this.sync_user_id(new_user);
                this.getChartData(isNaN(new_tab) ? 0 : new_tab);
                return;
            }
            
            // first time activated...
            if (this.all_users.length == 0)
                this.getChartData(new_tab);
            
            // see if props changed when deactive
            else if (this.date_range && this.date_range !== this.data_date_range)
                this.getChartData(new_tab);
            else {
                // ensure the route query contains "user=<data_user_id>"
                if (!isNaN(new_tab)) this.tab_index = new_tab;
                this.update_route();
            }

        },

        watch: {
            // watch props for changes
            'date_range': function() {
                this.getChartData();
            }
        },

        mounted: function() {
            this.sync_user_id(this.$route.query.user || '');
        },
        
        methods: {
            update_route: function() {
                // ensure the route contains query element
                // "user=<data_user_id>" for the loaded data
                if (this.data_user_id && this.data_user_id !== this.$route.query.user) {
                    var route = Object.assign({}, this.$route);
                    route.query = Object.assign({}, this.$route.query);
                    route.query.user=this.data_user_id;
                    this.$router.replace(route);
                }
            },

            sync_user_id: function(user_id) {
                // manually update "model" for <input> to avoid
                // slowness with large tables
                this.user_id = user_id;
                this.$refs.user_id_input.value = user_id;
            },
            
            change_user: function() {
                this.getChartData(0);
            },

            combine_sent_mail_fields: function() {
                // remove these fields...
                this.sent_mail.combine_fields([
                    'sent_id',
                    'spam_score',
                    'delivery_info',
                    'delivery_connection_info',
                ]);
                
                // combine fields 'envelope_from' and 'rcpt_to'
                this.sent_mail.combine_fields(
                    'envelope_from',
                    'rcpt_to',
                    (v, key, item) => {
                        if (item.envelope_from == this.data_user_id)
                            return v;
                        return `${v} (FROM: ${item.envelope_from})`;
                    });
                
                // combine fields 'relay', 'delivery_connection'
                this.sent_mail.combine_fields(
                    'delivery_connection',
                    'relay',
                    (v, key, item) => {
                        if (item.service == 'lmtp')
                            return '';
                        var s = v.split('[', 1);
                        // remove the ip address
                        v = s[0];
                        if (!item.delivery_connection ||
                            item.delivery_connection == 'trusted' ||
                            item.delivery_connection == 'verified')
                        {
                            return v;
                        }
                        return `${v}: ${item.delivery_connection}`;
                    });

            },

            combine_received_mail_fields: function() {
                // remove these fields
                this.received_mail.combine_fields([
                    'remote_host',
                    'remote_ip',
                    'dkim_reason',
                    'dmarc_reason',
                    'failure_info',
                    'postgrey_reason',
                    'postgrey_delay',
                    'spam_score',
                    'orig_to',
                    'message_id',
                    'lmtp_id',
                ]);
                // combine fields 'envelope_from' and 'sasl_username'
                var f = this.received_mail.combine_fields(
                    'sasl_username',
                    'envelope_from',
                    (v, key, item) => {
                        if (!item.sasl_username || item.envelope_from == item.sasl_username)
                            return v;
                        return `${v} (${item.sasl_username})`;
                    });
                f.label = 'Envelope From (user)';
            },

            combine_imap_conn_summary_fields: function() {
                // remove 'first_conn_time'
                this.imap_conn_summary.combine_fields('first_connection_time');
                // clear the label for the 'total' column (pct)
                const f_total = this.imap_conn_summary.get_field('total');
                f_total.label = '';
            },

            combine_imap_details_fields: function() {
                // remove these fields
                this.imap_details.combine_fields([
                    'remote_host',
                    'disposition',
                ]);
            },


            get_row_limit: function() {
                return UserSettings.get().row_limit;
            },

            update_sent_mail_rowVariant: function() {
                // there is 1 row for each recipient of a message
                // - give all rows of the same message the same
                // color
                this.sent_mail.apply_rowVariant_grouping('info', item => {
                    if (this.show_only_flagged && !item._flagged)
                        return null;
                    return item.sent_id;
                });
            },

            show_only_flagged_change: function() {
                // 'change' event callback for checkbox
                this.update_sent_mail_rowVariant();
                // trigger BV to filter or not filter via
                // reactive `show_only_flagged_filter`
                this.show_only_flagged_filter=
                    (this.show_only_flagged ? 'yes' : null );                
            },
                

            table_filter_cb: function(item, filter) {
                // when filter is non-null, called by BV for each row
                // to determine whether it will be filtered (false) or
                // included in the output (true)
                return item._flagged;
            },
            
            
            getChartData: function(switch_to_tab) {
                if (this.all_users.length == 0) {
                    this.$emit('loading', 1);
                    axios.get('reports/uidata/user-list').then(response => {
                        this.all_users = response.data;
                        
                    }).catch(error => {
                        this.$root.handleError(error);
                        
                    }).finally(() => {
                        this.$emit('loading', -1);
                    });
                }

                
                if (!this.date_range || !this.user_id) {
                    return;
                }

                this.$emit('loading', 1);
                const promise = axios.post('reports/uidata/user-activity', {
                    row_limit: this.get_row_limit(),
                    user_id: this.user_id.trim(),
                    start_date: this.date_range[0],
                    end_date: this.date_range[1]
                    
                }).then(response => {

                    this.data_user_id = this.user_id.trim();
                    this.data_date_range = this.date_range;
                    if (!isNaN(switch_to_tab))
                        this.tab_index = switch_to_tab;
                    this.update_route();
                    this.$emit('change', this.data_user_id);
                    this.show_only_flagged = false;
                    this.show_only_flagged_filter = null;

                    /* setup sent_mail */
                    this.sent_mail = new MailBvTable(
                        response.data.sent_mail, {
                            _showDetails: true
                        });
                    this.combine_sent_mail_fields();
                    this.sent_mail
                        .flag_fields()
                        .get_field('connect_time')
                        .add_tdClass('text-nowrap');
                    this.update_sent_mail_rowVariant();
                    

                    /* setup received_mail */
                    this.received_mail = new MailBvTable(
                        response.data.received_mail, {
                            _showDetails: true
                        });
                    this.combine_received_mail_fields();
                    this.received_mail
                        .flag_fields()
                        .get_field('connect_time')
                        .add_tdClass('text-nowrap');

                    
                    /* setup imap_conn_summary */
                    this.imap_conn_summary = new MailBvTable(
                        response.data.imap_conn_summary
                    );
                    this.combine_imap_conn_summary_fields();
                    this.imap_conn_summary.flag_fields();
                    ['last_connection_time','count']
                        .forEach(name => {
                            const f = this.imap_conn_summary.get_field(name);
                            f.add_cls('text-nowrap', 'tdClass');
                        });

                    /* clear imap_details */
                    this.imap_details = null;

                }).catch(error => {
                    this.$root.handleError(error);
                    
                }).finally(() => {
                    this.$emit('loading', -1);
                });

                return promise;
            },

            row_clicked: function(item, index, event) {
                item._showDetails = ! item._showDetails;
            },

            show_message_headers: function(lmtp_id) {
                // set the lmtp_id that component message-headers-view
                // searches for
                this.lmtp_id = lmtp_id;
                
                // show the modal dialog
                this.$refs.message_headers_modal.show();
            },

            load_imap_details: function(item, index, event) {
                this.$emit('loading', 1);
                this.imap_details = null;
                const promise = axios.post('reports/uidata/imap-details', {
                    row_limit: this.get_row_limit(),
                    user_id: this.user_id.trim(),
                    start_date: this.date_range[0],
                    end_date: this.date_range[1],
                    disposition: item.disposition,
                    remote_host: item.remote_host
                }).then(response => {
                    this.imap_details = new MailBvTable(
                        response.data.imap_details
                    );
                    this.combine_imap_details_fields();
                    this.imap_details.get_field('connect_time')
                        .add_tdClass('text-nowrap');
                    this.imap_details.get_field('disconnect_time')
                        .add_tdClass('text-nowrap');
                    this.imap_details._desc =
                        `${item.remote_host}/${item.disposition}`;
                    
                }).catch(error => {
                    this.$root.handleError(error);
                    
                }).finally( () => {
                    this.$emit('loading', -1);
                });
            }
            
        }
        
    })}).catch((e) => {
        reject(e);
    });
    
});
