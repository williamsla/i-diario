# frozen_string_literal: true

# Cache em memória por thread/request para reduzir N+1 durante geração de relatórios.
#
# Escopo: apenas a request atual (limpo no around_action do ApplicationController).
# Não expira por tempo — ao fim da request o conteúdo é descartado.
# Não é compartilhado entre usuários, requests ou threads do Puma.
class ReportQueryCache
  def self.fetch(key)
    return store[key] if store.key?(key)

    store[key] = yield
  end

  def self.clear!
    Thread.current[:report_query_cache] = {}
  end

  def self.store
    Thread.current[:report_query_cache] ||= {}
  end
  private_class_method :store
end
