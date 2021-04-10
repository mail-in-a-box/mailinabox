/*
  set of charts/tables showing messages received from internet servers

*/

import chart_multi_line_timeseries from "./chart-multi-line-timeseries.js";
import chart_table from "./chart-table.js";

import { ChartPrefs, TimeseriesData, BvTable } from "./charting.js";


export default Vue.component('panel-messages-received', function(resolve, reject) {
    axios.get('reports/ui/panel-messages-received.html').then((response) => { resolve({

        template: response.data,
        
        props: {
            date_range: Array,
            binsize: Number,
            user_link: Object,
            remote_sender_email_link: Object,
            remote_sender_server_link: Object,
            width: { type:Number, default: ChartPrefs.default_width },
            height: { type:Number, default: ChartPrefs.default_height },
        },

        components: {
            'chart-multi-line-timeseries': chart_multi_line_timeseries,
            'chart-table': chart_table,
        },
        
        data: function() {
            return {
                data_date_range: null,
                data_received: null,
                top_senders_by_count: null,
                top_senders_by_size: null,
                top_hosts_by_spam_score: null,
                top_user_receiving_spam: null,
            };
        },
        
        computed: {
        },
        
        activated: function() {
            // see if props changed when deactive
            if (this.date_range && this.date_range !== this.data_date_range)
                this.getChartData();            
        },
        
        watch: {
            // watch props for changes
            'date_range': function() {
                this.getChartData();
            }
        },
        
        methods: {
            link_to_user: function(user_id) {
                // add user=user_id to the user_link route
                var r = Object.assign({}, this.user_link);
                r.query = Object.assign({}, this.user_link.query);
                r.query.user = user_id;
                return r;
            },
            link_to_remote_sender_email: function(email) {
                // add email=email to the remote_sender_email route
                var r = Object.assign({}, this.remote_sender_email_link);
                r.query = Object.assign({}, this.remote_sender_email_link.query);
                r.query.email = email;
                return r;
            },
            link_to_remote_sender_server: function(server) {
                // add server=server to the remote_sender_server route
                var r = Object.assign({}, this.remote_sender_server_link);
                r.query = Object.assign({}, this.remote_sender_server_link.query);
                r.query.server = server;
                return r;
            },

            getChartData: function() {
                this.$emit('loading', 1);
                axios.post('reports/uidata/messages-received', {
                    'start': this.date_range[0],
                    'end': this.date_range[1],
                    'binsize': this.binsize,
                }).then(response => {
                    this.data_date_range = this.date_range;
                    var ts = new TimeseriesData(response.data.ts_received);
                    this.data_received = ts;

                    [ 'top_senders_by_count',
                      'top_senders_by_size',
                      'top_hosts_by_spam_score',
                      'top_user_receiving_spam'
                    ].forEach(item => {
                        this[item] = response.data[item];
                        BvTable.setFieldDefinitions(
                            this[item].fields,
                            this[item].field_types
                        );
                    });
                    
                }).catch(error => {
                    this.$root.handleError(error);
                }).finally(() => {
                    this.$emit('loading', -1);
                });
            },
            
        }
        
        
    })}).catch((e) => {
        reject(e);
    });
    
});

