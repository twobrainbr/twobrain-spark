<script setup>
import HeaderActions from './HeaderActions.vue';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';

defineProps({
  avatarUrl: {
    type: String,
    default: '',
  },
  introHeading: {
    type: String,
    default: '',
  },
  introBody: {
    type: String,
    default: '',
  },
  showPopoutButton: {
    type: Boolean,
    default: false,
  },
});

const { formatMessage } = useMessageFormatter();
</script>

<template>
  <header
    class="header-expanded pt-6 pb-4 px-5 relative box-border w-full bg-transparent"
  >
    <div class="flex items-start justify-between">
      <img
        v-if="avatarUrl"
        class="h-12 rounded-full"
        :src="avatarUrl"
        alt="Avatar"
      />
      <span v-else class="i-lucide-message-circle size-12 text-n-slate-12" />
      <HeaderActions
        :show-popout-button="showPopoutButton"
        :show-end-conversation-button="false"
      />
    </div>
    <h2
      v-dompurify-html="introHeading"
      class="mt-4 text-2xl mb-1.5 font-medium text-n-slate-12 line-clamp-4"
    />
    <p
      v-dompurify-html="formatMessage(introBody)"
      class="text-lg leading-normal text-n-slate-11 [&_a]:underline line-clamp-6"
    />
  </header>
</template>
