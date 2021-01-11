/*
 * reports index page
 */ 



const app = {
    router: new VueRouter({
        routes: [
            { path: '/', component: Vue.component('page-reports-main') },
            { path: '/settings', component: Vue.component('page-settings') },
            { path: '/:panel', component: Vue.component('page-reports-main') },
        ],
        scrollBehavior: function(to, from, savedPosition) {
            if (savedPosition) {
                return savedPosition
            }
        },
    }),
    
    components: {
        'page-settings': Vue.component('page-settings'),
        'page-reports-main': Vue.component('page-reports-main'),
    },
        
    data: {
        me: null,
    },

    mounted: function() {
        this.getMe();
    },
        
    methods: {
        getMe: function() {
            axios.get('me').then(response => {
                this.me = new Me(response.data);
            }).catch(error => {
                this.handleError(error);
            });
        },

        handleError: function(error) {
            if (error instanceof AuthenticationError) {
                console.log(error);
                window.location = '/admin';
                return;
            }
            
            console.error(error);
            if (error instanceof ReferenceError) {
                // uncaught coding bug, ignore
                return;
            }
            if (error.status && error.reason)
            {
                // axios
                error = error.reason;
            }
            this.$nextTick(() => {alert(''+error) });
        }
    }
};



function init_app() {
    init_axios_interceptors();
    
    UserSettings.load().then(settings => {
        new Vue(app).$mount('#app');
    }).catch(error => {
        alert('' + error);
    });
}
