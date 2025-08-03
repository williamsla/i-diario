import Vue from 'vue/dist/vue.js'

import ProfileChanger from '../components/ProfileChanger.vue'
import Multiselect from 'vue-multiselect'
import RegisterContentModal from '../components/RegisterContentModal.vue'


Vue.component('multiselect', Multiselect)

new Vue({
  el: '#profile-selection',
  data: { },
  components: {
    'b-profile-changer': ProfileChanger,
    'multiselect': Multiselect
  }
})

document.addEventListener('DOMContentLoaded', () => {
  const el = document.getElementById('register-content-app')
  if (el) {
    new Vue({
      el,
      components: {
        'register-content-modal': RegisterContentModal
      },
      data() {
        return {
          showModal: false,
          disciplines: JSON.parse(el.dataset.disciplines)
        }
      }
    })
  }
})