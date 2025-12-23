module IeducarApi
  class StudentAverages < Base
    def fetch(params = {})
      params.reverse_merge!(
        path: 'module/Api/Boletim',
        resource: 'media-geral'
      )

      raise ApiError, 'É necessário informar o código do aluno' if params[:aluno_id].blank?
      raise ApiError, 'É necessário informar o código da turma' if params[:turma_id].blank?
      raise ApiError, 'É necessário informar o código do componente curricular' if params[:componente_curricular_id].blank?
      raise ApiError, 'É necessário informar o código da etapa' if params[:etapa].blank?

      super
    end
  end
end

