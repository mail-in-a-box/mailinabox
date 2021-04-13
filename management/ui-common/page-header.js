var spinner = Vue.component('spinner', {
    template: '<span class="spinner-border spinner-border-sm"></span>'
});

var header = Vue.component('page-header', function(resolve, reject) {
    axios.get('ui-common/page-header.html').then((response) => { resolve({

        props: {
            header_text: { type: String, required: true },
            loading_counter: { type: Number, required: true }
        },
        
        template: response.data
                        
    })}).catch((e) => {
        reject(e);
    });

});

export { spinner, header as default };
