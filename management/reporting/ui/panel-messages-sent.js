/*
  set of charts/tables showing messages sent by local users
  - number of messages sent over time
    - delivered locally
    - delivered remotely
  - top senders

  emits:
     'loading'    event=number
*/

Vue.component('panel-messages-sent', function(resolve, reject) {
    axios.get('reports/ui/panel-messages-sent.html').then((response) => { resolve({

        template: response.data,
        
        props: {
            date_range: Array,  // YYYY-MM-DD strings (UTC)
            binsize: Number,    // for timeseries charts, in minutes
            // to enable clickable users, specify the route in
            // user_link. the user_id will be added to the
            // route.query as user=user_id. If set to 'true', the
            // current route will be used.
            user_link: Object,
            width: { type:Number, default: ChartPrefs.default_width },
            height: { type:Number, default: ChartPrefs.default_height },
        },

        components: {
            'chart-multi-line-timeseries': Vue.component('chart-multi-line-timeseries'),
            'chart-stacked-bar-timeseries': Vue.component('chart-stacked-bar-timeseries'),
            'chart-pie': Vue.component('chart-pie'),
            'chart-table': Vue.component('chart-table'),
        },
        
        data: function() {
            return {
                data_date_range: null,
                data_sent: null,
                data_recip: null,
                data_recip_pie: null,
                top_senders_by_count: null,
                top_senders_by_size: null,
            };
        },
        
        computed: {
            height_sent: function() {
                return this.height / 2;
            },
            
            height_recip: function() {
                return this.height / 2;
            },
            
            radius_recip_pie: function() {
                return this.height /5;
            },
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
            
            getChartData: function() {
                this.$emit('loading', 1);                
                axios.post('reports/uidata/messages-sent', {
                    'start': this.date_range[0],
                    'end': this.date_range[1],
                    'binsize': this.binsize,
                }).then(response => {
                    this.data_date_range = this.date_range;
                    var ts = new TimeseriesData(response.data.ts_sent);
                    this.data_sent = ts.dataView(['sent']);
                    this.data_recip = ts.dataView(['local','remote'])
                    
                    this.data_recip_pie = [{
                        name:'local',
                        value:d3.sum(ts.get_series('local').values)
                    }, {
                        name:'remote',
                        value:d3.sum(ts.get_series('remote').values)
                    }];
                    
                    this.top_senders_by_count =
                        response.data.top_senders_by_count;
                    BvTable.setFieldDefinitions(
                        this.top_senders_by_count.fields,
                        this.top_senders_by_count.field_types
                    );
                    
                    this.top_senders_by_size =
                        response.data.top_senders_by_size;
                    BvTable.setFieldDefinitions(
                        this.top_senders_by_size.fields,
                        this.top_senders_by_size.field_types
                    );
                    
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

