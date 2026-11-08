/**
 * @description Maps Repasse NomeSintese values to the 7 canonical macro-phase labels
 *              used as Stage__c on CommunicatorThread__c. Mirrors REPASSE_FILTER_GROUPS
 *              in communicatorChatFloatingButton.js — keep both in sync when phases change.
 */
public without sharing class CommunicatorRepassePhaseHelper {

    private static final Map<String, String> NOME_SINTESE_TO_MACRO_PHASE;
    private static final Map<String, String> NOME_SINTESE_NORMALIZED_TO_MACRO_PHASE;

    static {
        NOME_SINTESE_TO_MACRO_PHASE = new Map<String, String>{
            // Aguardando início
            'IR FUTURO'                      => 'Aguardando início',
            'ASSINATURA DE FORMULÁRIOS'      => 'Aguardando início',
            'AGUARDANDO PJ'                  => 'Aguardando início',
            'SFH'                            => 'Aguardando início',
            'VENDA DIRETA'                   => 'Aguardando início',
            'AGUARDANDO ENCERRAMENTO DE OBRA'=> 'Aguardando início',
            // Formulário
            'EMITIDO'                        => 'Formulário',
            'EM EMISSÃO'                     => 'Formulário',
            'AGENDADO'                       => 'Formulário',
            'DÉBITO DO FGTS'                 => 'Formulário',
            'AGENDAR ENTREVISTA MANUAL'      => 'Formulário',
            'VENDA NOVA'                     => 'Formulário',
            // Conferência de dossiê
            'MONTAGEM CEHOP'                 => 'Conferência de dossiê',
            'CONFERÊNCIA'                    => 'Conferência de dossiê',
            'PENDÊNCIA PARA ENVIO'           => 'Conferência de dossiê',
            'INCONFORME'                     => 'Conferência de dossiê',
            // Pendências
            'AGUARDANDO DOCUMENTOS'          => 'Pendências',
            'REAPROVAÇÃO DE CRÉDITO'         => 'Pendências',
            'ANÁLISE JURÍDICA'               => 'Pendências',
            'REANÁLISE JURÍDICA'             => 'Pendências',
            // Assinatura do repasse
            'FECHAMENTO DE VALORES'          => 'Assinatura do repasse',
            'APTO PARA ASSINATURA'           => 'Assinatura do repasse',
            'AGENDAR ASSINATURA MANUAL'      => 'Assinatura do repasse',
            'ASSINATURA AGENDADA'            => 'Assinatura do repasse',
            'PENDENCIA CONFERENCIA EXTERNA'  => 'Assinatura do repasse',
            'ASSINADO PENDÊNCIA SANADA'     => 'Assinatura do repasse',
            'ASSINADO COM PENDÊNCIA'         => 'Assinatura do repasse',
            'ASSINADO EM CONFERÊNCIA'        => 'Assinatura do repasse',
            'CONFERÊNCIA EXTERNA'            => 'Assinatura do repasse',
            'ASSINATURA PENDÊNCIA SANADA'    => 'Assinatura do repasse',
            'ASSINATURA BANCO'               => 'Assinatura do repasse',
            'ASSINATURA DIGITAL'             => 'Assinatura do repasse',
            'ASSINATURA FÍSICO'              => 'Assinatura do repasse',
            'AGUARDANDO REGISTRO'            => 'Assinatura do repasse',
            'CONTRATO CONFORME'              => 'Assinatura do repasse',
            // Retenção
            'TROCA RETENÇÃO'                 => 'Retenção',
            'TROCA COMERCIAL'                => 'Retenção',
            'EM NEGOCIAÇÃO'                  => 'Retenção',
            'FAZER CONTATO'                  => 'Retenção',
            'POSSÍVEL CESSÃO'                => 'Retenção',
            // Triagem
            'SEM CONTATO'                    => 'Triagem',
            'CESSÃO CONCLUÍDA'               => 'Triagem',
            'RETORNO'                        => 'Triagem',
            'RETORNO DA RETENÇÃO'            => 'Triagem',
            'RESTRIÇÃO'                      => 'Triagem',
            'RESTRIÇÃO SERASA/RF'            => 'Triagem',
            'SEM INTERESSE'                  => 'Triagem',
            'SEM INTERESSE NO REPASSE'       => 'Triagem',
            'NÃO ENQUADRADO'                 => 'Triagem',
            'NÃO LOCALIZADO'                 => 'Triagem'
        };

        NOME_SINTESE_NORMALIZED_TO_MACRO_PHASE = new Map<String, String>();
        for (String nomeSinteseValue : NOME_SINTESE_TO_MACRO_PHASE.keySet()) {
            String normalizedSinteseValue = normalizeText(nomeSinteseValue);
            if (String.isBlank(normalizedSinteseValue)) continue;
            NOME_SINTESE_NORMALIZED_TO_MACRO_PHASE.put(
                normalizedSinteseValue,
                NOME_SINTESE_TO_MACRO_PHASE.get(nomeSinteseValue)
            );
        }
    }

    /**
     * @description Maps a NomeSintese value (case-insensitive) to its canonical macro-phase label.
     * @param nomeSintese Raw NomeSintese string (e.g. 'IR FUTURO', 'Agendado').
     * @return Macro-phase label (e.g. 'Aguardando início'), or 'Outros' if the value is present but not mapped, or '' if blank.
     */
    public static String getMacroPhase(String nomeSintese) {
        if (String.isBlank(nomeSintese)) return '';
        String normalizedSinteseValue = normalizeText(nomeSintese);
        if (String.isBlank(normalizedSinteseValue)) return '';
        String result = NOME_SINTESE_NORMALIZED_TO_MACRO_PHASE.get(normalizedSinteseValue);
        return result != null ? result : 'Outros';
    }

    public static String getRepasseSinteseName(Repasse__c repasse) {
        if (repasse == null) return '';
        if (repasse.Sintese__r != null && String.isNotBlank(repasse.Sintese__r.Name)) {
            return repasse.Sintese__r.Name;
        }
        return String.isNotBlank(repasse.NomeSintese__c) ? repasse.NomeSintese__c : '';
    }

    public static Set<String> getNomeSinteseValuesByMacroPhaseKeyword(String keyword) {
        Set<String> nomeSinteseValues = new Set<String>();
        String normalizedKeyword = normalizeText(keyword);
        if (String.isBlank(normalizedKeyword)) return nomeSinteseValues;
        for (String nomeSinteseValue : NOME_SINTESE_TO_MACRO_PHASE.keySet()) {
            String macroPhaseValue = NOME_SINTESE_TO_MACRO_PHASE.get(nomeSinteseValue);
            if (normalizeText(macroPhaseValue).contains(normalizedKeyword)) {
                nomeSinteseValues.add(nomeSinteseValue);
            }
        }
        return nomeSinteseValues;
    }

    /**
     * @description Returns the current macro-phase of the latest Repasse linked to an Opportunity.
     * @param opportunityId Id of the Opportunity.
     * @return Macro-phase label, or '' if no Repasse exists or phase is unmapped.
     */
    public static String getRepasseMacroPhaseByOppId(Id opportunityId) {
        if (opportunityId == null) return '';
        Map<Id, Repasse__c> repasseMap = CommunicatorThreadService.getVisibleLatestRepassesByOpportunityIds(
            new Set<Id>{ opportunityId }
        );
        Repasse__c repasse = repasseMap.get(opportunityId);
        String repasseSinteseName = getRepasseSinteseName(repasse);
        if (String.isBlank(repasseSinteseName)) return '';
        return getMacroPhase(repasseSinteseName);
    }

    private static String normalizeText(String value) {
        if (String.isBlank(value)) return '';
        String normalizedValue = value.trim().toLowerCase();
        normalizedValue = normalizedValue.replaceAll('\\s+', ' ');
        normalizedValue = normalizedValue.replace('á', 'a').replace('à', 'a').replace('â', 'a').replace('ã', 'a');
        normalizedValue = normalizedValue.replace('é', 'e').replace('ê', 'e');
        normalizedValue = normalizedValue.replace('í', 'i');
        normalizedValue = normalizedValue.replace('ó', 'o').replace('ô', 'o').replace('õ', 'o');
        normalizedValue = normalizedValue.replace('ú', 'u').replace('ç', 'c');
        return normalizedValue;
    }
}