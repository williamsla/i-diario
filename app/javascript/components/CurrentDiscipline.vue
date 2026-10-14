<template>
  <div id="current-discipline-container"
       class="project-context"
       v-if="displayable">
    <span :class="{ required, label: true  }">
      Disciplina / Área de Conhecimento
    </span>

    <input type="hidden"
           name="user[current_knowledge_area_id]"
           v-model="selected.knowledge_area_id"
           v-if="selected" />

    <input type="hidden"
           name="user[current_discipline_id]"
           v-model="selected.discipline_id"
           v-if="selected" />

    <multiselect v-model="selected"
                 :options="selectOptions"
                 :group-values="groupValues"
                 :group-label="groupLabel"
                 :searchable="true"
                 :close-on-select="true"
                 :placeholder="isLoading ? 'Carregando...' : 'Selecione'"
                 :allow-empty="false"
                 :loading="isLoading"
                 :disabled="anyComponentLoading"
                 @input="disciplineHasBeenSelected"
                 track-by="id"
                 label="description"
                 deselect-label=""
                 select-label=""
                 selected-label="">
      <span slot="noResult">Não encontrado...</span>
      <span slot="noOptions">Não há disciplinas...</span>
    </multiselect>
  </div>
</template>

<script>
import axios from 'axios'
import { EventBus  } from "../packs/event-bus.js"

const DISCIPLINE_GROUPS = [
  { kind: 'discipline', label: 'Por disciplina' },
  { kind: 'knowledge_area', label: 'Por área de conhecimento' },
  { kind: 'both', label: 'Por disciplina e área de conhecimento' }
]

function disciplineSelectOptions (disciplines) {
  const list = Array.isArray(disciplines) ? disciplines : []
  const groups = DISCIPLINE_GROUPS.map((group) => ({
    label: group.label,
    items: list.filter((item) => (item.record_kind || 'discipline') === group.kind)
  })).filter((group) => group.items.length)

  if (groups.length < 2) {
    return list
  }

  return groups
}

export default {
  name: "b-current-discipline",
  props: [ 'anyComponentLoading', 'byTeacherProfile' ],
  data () {
    return {
      options: window.state.available_disciplines,
      selected: window.state.current_discipline,
      isLoading: false,
      classroom: null,
      role: null,
      required: false
    }
  },
  computed: {
    displayable () {
      return (this.isLoading || this.options.length) && this.classroom && !this.byTeacherProfile
    },
    selectOptions () {
      return disciplineSelectOptions(this.options)
    },
    grouped () {
      return this.selectOptions.length > 0 && Array.isArray(this.selectOptions[0].items)
    },
    groupValues () {
      return this.grouped ? 'items' : ''
    },
    groupLabel () {
      return this.grouped ? 'label' : ''
    }
  },
  methods: {
    setRequired() {
      if (this.classroom && _.isEmpty(this.classroom)) {
        this.required = false
        return
      }

      this.required = this.role && this.role.role_access_level !== 'parent' && this.role.role_access_level !== 'student'
    },
    disciplineHasBeenSelected() {
      EventBus.$emit("set-discipline", this.$data)
    },
    route (teacher) {
      let filters = {
        by_teacher_id: teacher.id,
        by_classroom_id: this.classroom.id,
      }

      return Routes.available_disciplines_pt_br_path({ filter: filters, format: 'json' })
    }
  },
  created: function () {
    EventBus.$on("set-classroom", (classroomData) => {
      this.classroom = classroomData.selected
      this.setRequired()
    })

    EventBus.$on("set-role", (roleData) => {
      this.role = roleData.selected
      this.setRequired()
    })

    EventBus.$on("fetch-disciplines", async (teacher) => {
      this.isLoading = true
      this.selected = null
      this.options = []

      this.disciplineHasBeenSelected()

      if (teacher) {
        await axios
          .get(this.route(teacher))
          .then(({ data }) => {
            this.options = data.disciplines

            if (this.options.length === 1) {
              this.selected = this.options[0]
            }
          })
      }

      this.isLoading = false
      this.disciplineHasBeenSelected()
    })
  },
  mounted () {
    this.disciplineHasBeenSelected()
  }
}
</script>

<style>
#current-discipline-container {
  width: 225px;
}
@media (max-width: 1365px) {
  #current-discipline-container {
    width: 100%;
  }
}

#current-discipline-container .multiselect__option--group {
  background: #eef2f4;
  color: #5c6b73;
  cursor: default;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.02em;
  text-transform: uppercase;
}

#current-discipline-container .multiselect__option--group.multiselect__option--highlight,
#current-discipline-container .multiselect__option--group:hover {
  background: #eef2f4;
  color: #5c6b73;
}

#current-discipline-container .multiselect__option--group.multiselect__option--highlight:after,
#current-discipline-container .multiselect__option--group:hover:after {
  background: transparent;
  content: none;
}
</style>
