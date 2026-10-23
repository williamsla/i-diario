module IeducarApi
  # O envio de notas (module/Api/Diario, resource notas) grava o valor e não apaga.
  # A remoção fica no diário antigo: oper=delete, resource=nota, por matrícula.
  class DeleteExamScore < Base
    def send_delete(params = {})
      params.reverse_merge!(
        path: 'module/Avaliacao/diarioApi',
        resource: 'nota',
        oper: 'delete',
        ignore_modified: true
      )

      raise ApiError, 'É necessário informar a etapa' if params[:etapa].blank?
      raise ApiError, 'É necessário informar a matrícula' if params[:matricula_id].blank?
      raise ApiError, 'É necessário informar o componente curricular' if params[:componente_curricular_id].blank?

      fetch(params)
    end
  end
end
