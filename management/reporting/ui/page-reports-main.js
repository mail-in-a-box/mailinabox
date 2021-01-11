Vue.component('page-reports-main', function(resolve, reject) {
    axios.get('reports/ui/page-reports-main.html').then((response) => { resolve({

        template: response.data,

        components: {
            'page-layout': Vue.component('page-layout'),
            'reports-page-header': Vue.component('reports-page-header'),
            'date-range-picker': Vue.component('date-range-picker'),
            'panel-messages-sent': Vue.component('panel-messages-sent'),
            'panel-messages-received': Vue.component('panel-messages-received'),
            'panel-flagged-connections': Vue.component('panel-flagged-connections'),
            'panel-user-activity': Vue.component('panel-user-activity'),
        },
        
        data: function() {
            return {
                // page-header loading spinner
                loading: 0,
                
                // panels
                panel: this.$route.params.panel || '',

                // date picker - the range, if in the route, is set
                // via date_change(), called during date picker
                // create()
                range_utc: null,  // Array(2): Date objects (UTC)
                range: null, // Array(2): YYYY-MM-DD (localtime)
                range_type: null, // String: "custom","ytd","mtd", etc
            };
        },

        beforeRouteUpdate: function(to, from, next) {
            //console.log(`page route update: to=${JSON.stringify({path:to.path, query:to.query})}  ....  from=${JSON.stringify({path:from.path, query:from.query})}`);
            this.panel = to.params.panel;
            // note: the range is already set in the class data
            //
            //  1. at component start - the current range is extracted
            //     from $route by get_route_range() and passed to the
            //     date picker as a prop, which subsequently
            //     $emits('change') during creation where date_change()
            //     updates the class data.
            //
            //  2. during user interaction - the date picker
            //     $emits('change') where date_change() updates the
            //     class data.
            next();
        },
        
        methods: {
            get_start_range: function(to, default_range) {
                if (to.query.range_type) {
                    return to.query.range_type;
                }
                else if (to.query.start && to.query.end) {
                    // start and end must be YYYY-MM-DD (localtime)
                    return [
                        to.query.start,
                        to.query.end
                    ];
                }
                else {
                    return default_range;
                }
            },
            
            get_binsize: function() {
                if (! this.range_utc) return 0;
                return TimeseriesData.binsizeOfRange(this.range_utc);
            },

            date_change: function(evt) {
                // date picker 'change' event
                this.range_type = evt.range_type;
                this.range_utc = evt.range_utc;
                this.range = evt.range;
                var route = this.get_route(this.panel);
                if (! evt.init) {
                    this.$router.replace(route);
                }
            },

            get_route: function(panel, ex_query) {
                // return vue-router route to `panel`
                // eg: "/<panel>?start=YYYY-MM-DD&end=YYYY-MM-DD"
                //
                // additional panel query elements should be set in
                // the panel's activate method
                var route = { path: panel };
                if (this.range_type != 'custom') {
                    route.query = {
                        range_type: this.range_type
                    };
                }
                else {
                    route.query = {
                        start: this.range[0],
                        end: this.range[1]
                    };
                }
                Object.assign(route.query, ex_query);
                return route;
            },
            
        }
    })}).catch((e) => {
        reject(e);
    });
    
});
