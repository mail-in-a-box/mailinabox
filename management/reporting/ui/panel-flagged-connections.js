/////
///// This file is part of Mail-in-a-Box-LDAP which is released under the
///// terms of the GNU Affero General Public License as published by the
///// Free Software Foundation, either version 3 of the License, or (at
///// your option) any later version. See file LICENSE or go to
///// https://github.com/downtownallday/mailinabox-ldap for full license
///// details.
/////


import chart_multi_line_timeseries from "./chart-multi-line-timeseries.js";
import chart_stacked_bar_timeseries from "./chart-stacked-bar-timeseries.js";
import chart_pie from "./chart-pie.js";
import chart_table from "./chart-table.js";

import { ChartPrefs, TimeseriesData, BvTable, ConnectionDisposition } from "./charting.js";


export default Vue.component('panel-flagged-connections', function(resolve, reject) {
    axios.get('reports/ui/panel-flagged-connections.html').then((response) => { resolve({

        template: response.data,
        
        props: {
            date_range: Array,  // YYYY-MM-DD strings (UTC)
            binsize: Number,    // for timeseries charts, in minutes
            user_link: Object,   // a route
            remote_sender_email_link: Object, // a route
            remote_sender_server_link: Object, // a route
            width: { type:Number, default: ChartPrefs.default_width },
            height: { type:Number, default: ChartPrefs.default_height },
        },

        components: {
            'chart-multi-line-timeseries': chart_multi_line_timeseries,
            'chart-stacked-bar-timeseries': chart_stacked_bar_timeseries,
            'chart-pie': chart_pie,
            'chart-table': chart_table,
        },

        computed: {
            radius_pie: function() {
                return this.height / 5;
            },
            linechart_height: function() {
                return this.height / 2;
            }
        },
        
        data: function() {
            return {
                data_date_range: null,
                colors: ChartPrefs.colors,
                failed_logins: null,  // TimeseriesData
                suspected_scanners: null, // TimeseriesData
                connections_by_disposition: null,  // pie chart data
                disposition_formatter: ConnectionDisposition.formatter,
                reject_by_failure_category: null, // pie chart data
                top_hosts_rejected: null,  // table
                insecure_inbound: null,  // table
                insecure_outbound: null, // table
            };
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
            link_to_user: function(user_id, tab) {
                // add user=user_id to the user_link route
                var r = Object.assign({}, this.user_link);
                r.query = Object.assign({}, this.user_link.query);
                r.query.user = user_id;
                r.query.tab = tab;
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
                axios.post('reports/uidata/flagged-connections', {
                    'start': this.date_range[0],
                    'end': this.date_range[1],
                    'binsize': this.binsize,
                }).then(response => {
                    this.data_date_range = this.date_range;

                    // line charts
                    var ts = new TimeseriesData(response.data.flagged);
                    this.failed_logins =
                        ts.dataView(['failed_login_attempt']);
                    this.suspected_scanners =
                        ts.dataView(['suspected_scanner']);
                    
                    // pie chart for connections by disposition
                    this.connections_by_disposition =
                        response.data.connections_by_disposition;

                    // pie chart for reject by failure_category
                    this.reject_by_failure_category =
                        response.data.reject_by_failure_category;

                    // table of top 10 hosts rejected by failure_category
                    this.top_hosts_rejected =
                        new BvTable(response.data.top_hosts_rejected);

                    // insecure connections tables
                    this.insecure_inbound
                        = new BvTable(response.data.insecure_inbound);
                    this.insecure_outbound
                        = new BvTable(response.data.insecure_outbound);
                    
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

