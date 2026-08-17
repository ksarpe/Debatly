"use client";

import { useParams, useRouter } from "next/navigation";
import QuestionEditor from "../../../components/QuestionEditor";

/**
 * Standalone editor route. Kept for "+ Nowe pytanie" and deep links —
 * editing from the list happens inline (see app/page.jsx).
 */
export default function QuestionEditorPage() {
  const { id } = useParams();
  const router = useRouter();
  return (
    <QuestionEditor
      questionId={id}
      onBack={() => router.push("/")}
      onCreated={(newId) => router.replace(`/q/${newId}`)}
      onAfterDelete={() => router.replace("/")}
    />
  );
}
