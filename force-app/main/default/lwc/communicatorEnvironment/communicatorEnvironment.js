import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import FORM_FACTOR from '@salesforce/client/formFactor';

export const SALESFORCE_APP_DISABLED_MESSAGE =
    'Funcionalidade desabilitada: não é compatível com o app da Salesforce.';

const EXPERIENCE_CLOUD_PATH_PATTERN = /\/s(\/|$)/;

function isExperienceCloudSite() {
    try {
        return EXPERIENCE_CLOUD_PATH_PATTERN.test(window.location.pathname || '');
    } catch (error) {
        return false;
    }
}

/**
 * Indica se o componente está rodando no app mobile da Salesforce.
 * Desktop (core) e Experience Cloud (comunidade) retornam false.
 */
export function isSalesforceMobileApp(mobileMode = false) {
    if (mobileMode === true) return true;
    return FORM_FACTOR === 'Small' && !isExperienceCloudSite();
}

export function buildDisabledFeatureToast() {
    return new ShowToastEvent({
        title: SALESFORCE_APP_DISABLED_MESSAGE,
        variant: 'warning'
    });
}
