<template>
  <div class="modal-mask">
    <div class="modal-wrapper">
      <div class="modal-container p-4">

        <div class="modal-header d-flex justify-content-between align-items-center mb-3">
          <h5 class="modal-title">Registrar conteúdo do dia</h5>
          <button type="button" class="btn-close" @click="$emit('close')"></button>
        </div>

        <div class="modal-body">
          <div class="table-responsive">
            <table class="table table-bordered">
              <thead class="table-light">
                <tr>
                  <th>Disciplina</th>
                  <th>Aulas</th>
                  <th>Conteúdo</th>
                  <th>Habilidade</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="(disciplina, index) in contents" :key="index">
                  <td>{{ disciplina.name }}</td>
                  <td>
                    <select v-model="contents[index].lesson_count" class="form-select form-select-sm">
                      <option v-for="n in 5" :key="n" :value="n">{{ n }}</option>
                    </select>
                  </td>
                  <td>
                    <input type="text" v-model="contents[index].content" class="form-control form-control-sm" />
                  </td>
                  <td>
                    <select class="form-control" :name="`recorded_content[bncc_skill][]`" v-model="disciplina.bncc_skill">
                      <option disabled value="">Selecione uma habilidade</option>
                      <option v-for="skill in disciplina.skills" :key="skill.id" :value="skill.description">
                        {{ skill.description }}
                      </option>
                    </select>
                  </td>

                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div class="modal-footer mt-3 d-flex justify-content-end">
          <button class="btn btn-secondary me-2" @click="$emit('close')">Cancelar</button>
          <button class="btn btn-primary" @click="submit">Salvar</button>
        </div>

      </div>
    </div>
  </div>
</template>

<script>
export default {
  props: ['disciplines', 'classroomId', 'recordDate'],
  data() {
    return {
      contents: []
    }
  },
  mounted() {
    console.log('RegisterContentModal montado!');
    console.log('mounted disciplines:', this.disciplines);
    console.log('mounted classroom:', this.classroomId);
    console.log('mounted record_at:', this.recordDate);

    this.initializeContents();
    this.fetchSkills();
  },
  
  methods: {
    initializeContents() {
      this.contents = this.disciplines.map(discipline => ({
        ...discipline,
        classes: 1,
        content: '',
        bncc_skill: '',
        skills: [] // será preenchido depois
      }));
    },

    fetchSkills() {
      this.contents.forEach((discipline, index) => {
        fetch(`/habilidades/${discipline.id}.json`)
          .then(response => response.json())
          .then(data => {
            this.contents[index].skills = data.habilidades || [];
          })
          .catch(err => {
            console.error(`Erro ao buscar habilidades da disciplina ${discipline.id}:`, err);
          });
      });
    },

    submit() {
      console.log('Enviar para API existente...', {
        classroom_id: this.classroomId,
        record_date: this.recordDate,
        contents: this.contents
      });

      // Aqui você pode fazer o POST como no formulário de /registros-de-conteudos-por-disciplina/novo
      // ou emitir um evento para o pai salvar
      this.$emit('close');
    }
  }
}

</script>

<style scoped>
.modal-mask {
  position: fixed;
  z-index: 1050;
  top: 0;
  left: 0;
  width: 100vw;
  height: 100vh;
  background-color: rgba(0, 0, 0, 0.5);
  display: flex;
  align-items: center;
  justify-content: center;
}
.modal-wrapper {
  width: 95%;
  max-width: 1100px;
}
.modal-container {
  background-color: #fff;
  border-radius: 8px;
  overflow: hidden;
  max-height: 90vh;
  display: flex;
  flex-direction: column;
}
</style>
