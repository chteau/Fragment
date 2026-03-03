"use client"

import Image from 'next/image';
import Link from 'next/link';
import Beams from "@/components/Beams";
import { redirect, RedirectType } from 'next/navigation'


export default function HomePage() {
    redirect("/docs", RedirectType.replace)
    return (<></>);
}
