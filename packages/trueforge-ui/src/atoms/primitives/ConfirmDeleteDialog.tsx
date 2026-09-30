'use client';

import type { ReactNode } from 'react';

import { Button } from './Button.js';
import { CenteredModal } from './CenteredModal.js';

export type ConfirmDeleteDialogProps = {
  open: boolean;
  /** Resource name, used in the title — e.g. "wiki-qa". */
  itemName: string;
  /** What kind of thing it is, e.g. "skill" or "connector". */
  itemLabel: string;
  /**
   * Consequences beyond removing the row from this list. Omit when the delete is
   * contained — say so in the confirm label instead of implying there is none.
   */
  description?: string;
  confirmLabel?: string;
  busy?: boolean;
  onCancel: () => void;
  onConfirm: () => void;
  /** Extra body content, e.g. an in-use error with no retry affordance. */
  children?: ReactNode;
  footer?: ReactNode;
};

/**
 * Shared confirmation for destructive Settings actions.
 *
 * Every delete in Settings goes through this so the confirm step is never
 * skipped for one resource type and demanded for another. Deleting a connector
 * revokes every user's authorization for it; deleting a skill or model provider
 * only drops the row. Callers pass that difference in as `description` rather
 * than hard-coding it here.
 */
export function ConfirmDeleteDialog({
  open,
  itemName,
  itemLabel,
  description,
  confirmLabel = 'Remove',
  busy = false,
  onCancel,
  onConfirm,
  children,
  footer,
}: ConfirmDeleteDialogProps) {
  return (
    <CenteredModal
      open={open}
      onOpenChange={isOpen => {
        if (!isOpen) onCancel();
      }}
      title={`Remove ${itemName}`}
      description={description ?? `This ${itemLabel} will be removed from this workspace.`}
      contentSized
      className="md:max-w-xl"
    >
      {children ? <div className="space-y-4 px-5 py-5">{children}</div> : null}
      {footer ?? (
        <footer className="flex justify-end gap-2 border-t border-border px-5 py-4">
          <Button.Ghost type="button" onClick={onCancel} disabled={busy}>
            Cancel
          </Button.Ghost>
          <Button.Primary type="button" onClick={onConfirm} disabled={busy}>
            {confirmLabel}
          </Button.Primary>
        </footer>
      )}
    </CenteredModal>
  );
}
