Vue.component('page-layout', function(resolve, reject) {
    axios.get('ui-common/page-layout.html').then((response) => { resolve({

        template: response.data,
        
    })}).catch((e) => {
        reject(e);
    });

});
