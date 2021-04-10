
import page_layout from '../../ui-common/page-layout.js';
import reports_page_header from './reports-page-header.js';
import UserSettings from "./settings.js";
import { CaptureConfig } from "./settings.js";


export default Vue.component('page-settings', function(resolve, reject) {
    axios.get('reports/ui/page-settings.html').then((response) => { resolve({

        template: response.data,

        components: {
            'page-layout': page_layout,
            'reports-page-header': reports_page_header,
        },

        data: function() {
            return {
                from_route: null,
                loading: 0,

                // server status and config
                capture_config: null,
                config_changed: false,
                status: null,

                // capture config models that require processing
                // before the value is valid for `capture_config`, or
                // the `capture_config` value is used by multiple
                // elements (eg. one showing current state)
                capture: true,
                older_than_days: '',
                
                // user settings
                row_limit: '' + UserSettings.get().row_limit,
                row_limit_error: ''
            };
        },

        beforeRouteEnter: function(to, from, next) {
            next(vm => {
                vm.from_route = from;
            });
        },

        created: function() {
            this.loadData();
        },

        methods: {
            is_running: function() {
                return this.status[0] == 'running';
            },

            status_variant: function(status) {
                if (status == 'running') return 'success';
                if (status == 'enabled') return 'success';
                if (status == 'disabled') return 'warning';
                if (status === true) return 'success';
                return 'danger'
            },

            loadData: function() {
                this.loading += 1;
                Promise.all([
                    CaptureConfig.get(),
                    axios.get('/reports/capture/service/status')
                ]).then(responses => {
                    this.capture_config = responses[0];
                    if (this.capture_config.status !== 'error') {
                        this.older_than_days = '' +
                            this.capture_config.prune_policy.older_than_days;
                        this.capture = this.capture_config.capture;
                    }
                    this.status = responses[1].data;
                    this.config_changed = false;
                }).catch(error => {
                    this.$root.handleError(error);
                }).finally(() => {
                    this.loading -= 1;
                });
            },

            update_user_settings: function() {
                if (this.row_limit == '') {
                    this.row_limit_error = 'not valid';
                    return;
                }
                try {
                    const s = UserSettings.get();
                    s.row_limit = Number(this.row_limit);
                } catch(e) {
                    this.row_limit_error = e.message;
                }
            },

            config_changed_if: function(v, range_min, range_max, current_value) {
                v = Number(v);
                if (range_min !== null && v < range_min) return;
                if (range_max !== null && v > range_max) return;
                if (current_value !== null && v == current_value) return;
                this.config_changed = true;
            },

            save_capture_config: function() {
                this.loading+=1;
                var newconfig = Object.assign({}, this.capture_config);
                this.capture_config.prune_policy.older_than_days =
                    Number(this.older_than_days);
                newconfig.capture = this.capture;
                axios.post('/reports/capture/config', newconfig)
                    .then(response => {
                        this.loadData();
                    })
                    .catch(error => {
                        this.$root.handleError(error);
                    })
                    .finally(() => {
                        this.loading-=1;
                    });
            }
        }

    })}).catch((e) => {
        reject(e);
    });
});

    
