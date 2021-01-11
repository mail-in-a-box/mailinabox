/*
  details on the activity of a remote sender (envelope from)
*/

Vue.component('panel-remote-sender-activity', function(resolve, reject) {
    axios.get('reports/ui/panel-remote-sender-activity.html').then((response) => { resolve({

        template: response.data,
        
        props: {
            date_range: Array,  // YYYY-MM-DD strings (UTC)
        },

        data: function() {
            const usersetting_prefix = 'panel-rsa-';
            const sender_type = this.$route.query.email ? 'email' :
                  ( this.$route.query.server ? 'server' : 'email' );

            return {
                email: this.$route.query.email || '', /* v-model */
                server: this.$route.query.server || '', /* v-model */
                sender_type: sender_type, /* "email" or "server" only */
                
                tab_index: 0, /* v-model */
                
                show_only_flagged: false,
                show_only_flagged_filter: null,
                
                data_sender: null, /* sender for active table data */
                data_sender_type: null, /* "email" or "server" */
                data_date_range: null, /* date range for active table data */
                
                activity: null, /* table data */
                disposition_formatter: ConnectionDisposition.formatter,

                /* recent list */
                set_prefix: usersetting_prefix,
                recent_senders: UserSettings.get()
                    .get_recent_list(usersetting_prefix + sender_type),

                /* suggestions (from server) */
                select_list: { suggestions: [] }
            };
        },

        activated: function() {
            const new_email = this.$route.query.email;
            const new_server = this.$route.query.server;
            const new_sender_type = new_email ? 'email' :
                  ( new_server ? 'server' : null );

            var load = false;
            if (new_sender_type &&
                new_sender_type != this.sender_type)
            {
                this.sender_type = new_sender_type;
                load = true;
            }            
            if (this.sender_type == 'email' &&
                new_email &&
                new_email != this.email)
            {
                this.email = new_email;
                this.getChartData();
                return;
            }
            if (this.sender_type == 'server' &&
                new_server &&
                new_server != this.server)
            {
                this.server = new_server;
                this.getChartData();
                return;
            }
            
            // see if props changed when deactive
            if (load || this.date_range &&
                this.date_range !== this.data_date_range)
            {
                this.getChartData();
            }
            else
            {
                // ensure the route query contains the sender
                this.update_route();
            }
        },

        watch: {
            // watch props for changes
            'date_range': function() {
                this.getChartData();
            }
        },
        
        methods: {
            update_recent_list: function() {
                this.recent_senders = UserSettings.get()
                    .get_recent_list(this.set_prefix + this.sender_type);
            },
            
            update_route: function() {
                // ensure the route contains query element
                // "email=<data_sender>" or "server=<data_sender>"
                // for the loaded data
                if (this.data_sender && this.data_sender !== this.$route.query[this.sender_type]) {
                    var route = Object.assign({}, this.$route);
                    route.query = Object.assign({}, this.$route.query);
                    delete route.query.sender;
                    delete route.query.email;
                    route.query[this.sender_type] = this.data_sender;
                    this.$router.replace(route);
                }
            },
            
            change_sender: function() {
                axios.post('/reports/uidata/select-list-suggestions', {
                    type: this.sender_type == 'email' ?
                        'envelope_from' : 'remote_host',
                    query: this.sender_type == 'email' ?
                        this.email.trim() : this.server.trim(),
                    start_date: this.date_range[0],
                    end_date: this.date_range[1]
                }).then(response => {
                    if (response.data.exact) {
                        this.getChartData();
                    }
                    else {
                        this.select_list = response.data;
                        this.$refs.suggest_modal.show()
                    }
                }).catch(error => {
                    this.$root.handleError(error);
                });
            },

            choose_suggestion: function(suggestion) {
                this[this.sender_type] = suggestion;
                this.getChartData();
                this.$refs.suggest_modal.hide();
            },

            combine_fields: function() {
                // remove these fields...
                this.activity
                    .combine_fields([
                        'sent_id',
                        'sasl_username',
                        'spam_score',
                        'dkim_reason',
                        'dmarc_reason',
                        'postgrey_reason',
                        'postgrey_delay',
                        'category',
                        'failure_info',
                    ]);
            },

            get_row_limit: function() {
                return UserSettings.get().row_limit;
            },

            update_activity_rowVariant: function() {
                // there is 1 row for each recipient of a message
                // - give all rows of the same message the same
                // color
                this.activity.apply_rowVariant_grouping('info', (item, idx) => {
                    if (this.show_only_flagged && !item._flagged)
                        return null;
                    return item.sent_id;
                });                
            },
            
            show_only_flagged_change: function() {
                // 'change' event callback for checkbox
                this.update_activity_rowVariant();
                // trigger BV to filter or not filter via
                // reactive `show_only_flagged_filter`
                this.show_only_flagged_filter=
                    (this.show_only_flagged ? 'yes' : null );                
            },
                
            table_filter_cb: function(item, filter) {
                // when filter is non-null, this is called by BV for
                // each row to determine whether it will be filtered
                // (false) or included in the output (true)
                return item._flagged;
            },
            
            getChartData: function() {
                if (!this.date_range || !this[this.sender_type]) {
                    return;
                }

                this.$emit('loading', 1);
                axios.post('reports/uidata/remote-sender-activity', {
                    row_limit: this.get_row_limit(),
                    sender: this[this.sender_type].trim(),
                    sender_type: this.sender_type,
                    start_date: this.date_range[0],
                    end_date: this.date_range[1]
                    
                }).then(response => {
                    this.data_sender = this[this.sender_type].trim();
                    this.data_sender_type = this.sender_type;
                    this.data_date_range = this.date_range;
                    this.update_route();
                    this.recent_senders = UserSettings.get()
                        .add_to_recent_list(
                            this.set_prefix + this.sender_type,
                            this[this.sender_type]
                        );
                    this.show_only_flagged = false;
                    this.show_only_flagged_filter = null;
                    
                    /* setup table data */
                    this.activity =
                        new MailBvTable(response.data.activity, {
                            _showDetails: true
                        });
                    this.combine_fields();
                    this.activity
                        .flag_fields()
                        .get_field('connect_time')
                        .add_tdClass('text-nowrap');
                    this.update_activity_rowVariant();
                    
                }).catch(error => {
                    this.$root.handleError(error);
                    
                }).finally(() => {
                    this.$emit('loading', -1);
                });

            },

            row_clicked: function(item, index, event) {
                item._showDetails = ! item._showDetails;
            },
            
        }
        
    })}).catch((e) => {
        reject(e);
    });
    
});
