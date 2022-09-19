/////
///// This file is part of Mail-in-a-Box-LDAP which is released under the
///// terms of the GNU Affero General Public License as published by the
///// Free Software Foundation, either version 3 of the License, or (at
///// your option) any later version. See file LICENSE or go to
///// https://github.com/downtownallday/mailinabox-ldap for full license
///// details.
/////

export default Vue.component('chart-table', {
    props: {
        items: Array,
        fields: Array,
        caption: String,
        small: { type:Boolean, default:true }
    },

    /* <b-table-lite striped small :fields="fields_x" :items="items" caption-top><template #table-caption><span class="text-nowrap">{{caption}}</span></template></b-table>*/
    render: function(ce) {
        var scopedSlots= {
            'table-caption': props =>
                ce('span', { class: { 'text-nowrap':true }}, this.caption)
        };
        if (this.$scopedSlots) {
            for (var slotName in this.$scopedSlots) {
                scopedSlots[slotName] = this.$scopedSlots[slotName];
            }
        }
        var table = ce('b-table-lite', {
            props: {
                'striped': true,
                'small': this.small,
                'fields': this.fields_x,
                'items': this.items,
                'caption-top': true
            },
            attrs: {
                'thead-tr-class': 'h-1'
            },
            scopedSlots: scopedSlots
        });
        
        return table;
    },

    computed: {
        fields_x: function() {
            if (this.items.length == 0) {
                return [{
                    key: 'no data',
                    thClass: 'text-nowrap align-top'
                }];
            }
            return this.fields;
        }
    }

});
