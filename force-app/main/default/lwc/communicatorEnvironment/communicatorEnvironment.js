import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import FORM_FACTOR from '@salesforce/client/formFactor';
import COMMUNITY_ID from '@salesforce/community/Id';

export const SALESFORCE_APP_DISABLED_MESSAGE =
    'Funcionalidade desabilitada: não é compatível com o app da Salesforce.';

/**
 * Indica se o componente está rodando no app mobile da Salesforce.
 * Desktop (core) e Experience Cloud (comunidade) retornam false.
 */
export function isSalesforceMobileApp(mobileMode = false) {
    if (mobileMode === true) return true;
    return FORM_FACTOR === 'Small' && !COMMUNITY_ID;
}

export function buildDisabledFeatureToast() {
    return new ShowToastEvent({
        title: SALESFORCE_APP_DISABLED_MESSAGE,
        variant: 'warning'
    });
}
